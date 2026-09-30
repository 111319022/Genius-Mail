import BizError from '../error/biz-error';
import { t } from '../i18n/i18n';
import KvConst from '../const/kv-const';
import emailUtils from '../utils/email-utils';
import orm from '../entity/orm';
import email from '../entity/email';
import { and, count, eq } from 'drizzle-orm';
import { emailConst, isDel } from '../const/entity-const';

const APNS_HOST = {
	production: 'https://api.push.apple.com',
	sandbox: 'https://api.sandbox.push.apple.com'
};

const MAX_DEVICES = 10;
const PREVIEW_LEN = 180;
// APNs 要求 provider token 在 20~60 分钟内刷新
const JWT_TTL_MS = 45 * 60 * 1000;

let cachedJwt = null;

const pushService = {

	async register(c, params, userId) {
		const { deviceToken, environment, deviceName } = params;

		if (!/^[0-9a-fA-F]{32,200}$/.test(deviceToken || '')) {
			throw new BizError(t('invalidDeviceToken'));
		}

		const env = environment === 'sandbox' ? 'sandbox' : 'production';
		const devices = (await this.devices(c, userId)).filter(item => item.token !== deviceToken);

		devices.unshift({ token: deviceToken, env, name: deviceName || '', updateTime: new Date().toISOString() });

		await this.saveDevices(c, userId, devices.slice(0, MAX_DEVICES));
	},

	async unregister(c, params, userId) {
		const { deviceToken } = params;
		const devices = await this.devices(c, userId);
		await this.saveDevices(c, userId, devices.filter(item => item.token !== deviceToken));
	},

	async devices(c, userId) {
		return await c.env.kv.get(KvConst.PUSH_DEVICES + userId, { type: 'json' }) || [];
	},

	async saveDevices(c, userId, devices) {
		if (devices.length === 0) {
			await c.env.kv.delete(KvConst.PUSH_DEVICES + userId);
			return;
		}
		await c.env.kv.put(KvConst.PUSH_DEVICES + userId, JSON.stringify(devices));
	},

	isConfigured(c) {
		const { apns_key, apns_key_id, apns_team_id, apns_bundle_id } = c.env;
		return !!(apns_key && apns_key_id && apns_team_id && apns_bundle_id);
	},

	//收到新邮件时推送到该用户所有已注册的 iOS 装置
	async sendNewEmail(c, emailRow) {

		if (!emailRow?.userId || !this.isConfigured(c)) {
			return;
		}

		const devices = await this.devices(c, emailRow.userId);

		if (devices.length === 0) {
			return;
		}

		const badge = await this.unreadCount(c, emailRow.userId);
		const payload = this.buildEmailPayload(emailRow, badge);

		const results = await Promise.all(devices.map(device => this.send(c, device, payload, emailRow.emailId)));
		const invalidTokens = results.filter(item => item.invalid).map(item => item.token);

		if (invalidTokens.length > 0) {
			await this.saveDevices(c, emailRow.userId, devices.filter(item => !invalidTokens.includes(item.token)));
		}
	},

	//发送测试通知，返回每台装置的结果
	async sendTest(c, userId) {

		if (!this.isConfigured(c)) {
			throw new BizError(t('pushNotConfigured'));
		}

		const devices = await this.devices(c, userId);
		const payload = {
			aps: {
				alert: { title: 'Genius Mail', body: t('pushTestBody') },
				sound: 'default'
			}
		};

		return await Promise.all(devices.map(async device => {
			const result = await this.send(c, device, payload, 'test');
			return { env: device.env, name: device.name, tokenSuffix: device.token.slice(-8), ok: result.ok, reason: result.reason };
		}));
	},

	buildEmailPayload(emailRow, badge) {
		const sender = emailRow.name || emailRow.sendEmail || '';
		const preview = (emailUtils.formatText(emailRow.text) || emailUtils.htmlToText(emailRow.content))
			.replace(/\s+/g, ' ')
			.trim()
			.slice(0, PREVIEW_LEN);

		const body = emailRow.code ? `驗證碼 ${emailRow.code}\n${preview}` : preview;

		return {
			aps: {
				alert: {
					title: sender,
					subtitle: emailRow.subject || '',
					body: body || ' '
				},
				badge,
				sound: 'default',
				'thread-id': emailRow.toEmail || String(emailRow.accountId),
				'category': emailRow.code ? 'EMAIL_CODE' : 'EMAIL',
				'mutable-content': 1
			},
			emailId: emailRow.emailId,
			accountId: emailRow.accountId,
			toEmail: emailRow.toEmail,
			code: emailRow.code || ''
		};
	},

	async unreadCount(c, userId) {
		const row = await orm(c).select({ total: count() }).from(email).where(
			and(
				eq(email.userId, userId),
				eq(email.type, emailConst.type.RECEIVE),
				eq(email.isDel, isDel.NORMAL),
				eq(email.unread, emailConst.unread.UNREAD)
			)).get();
		return row?.total || 0;
	},

	async send(c, device, payload, collapseId) {
		try {
			const jwt = await this.providerToken(c);
			const res = await fetch(`${APNS_HOST[device.env] || APNS_HOST.production}/3/device/${device.token}`, {
				method: 'POST',
				headers: {
					'authorization': `bearer ${jwt}`,
					'apns-topic': c.env.apns_bundle_id,
					'apns-push-type': 'alert',
					'apns-priority': '10',
					'apns-collapse-id': String(collapseId || '')
				},
				body: JSON.stringify(payload)
			});

			if (res.ok) {
				return { token: device.token, ok: true, invalid: false };
			}

			const { reason } = await res.json().catch(() => ({}));
			console.warn(`APNs 推送失败 ${res.status} ${reason}`);

			const invalid = res.status === 410 || ['BadDeviceToken', 'DeviceTokenNotForTopic', 'Unregistered'].includes(reason);
			return { token: device.token, ok: false, invalid, reason: `${res.status} ${reason || ''}`.trim() };
		} catch (e) {
			console.error('APNs 推送异常: ', e);
			return { token: device.token, ok: false, invalid: false, reason: e.message };
		}
	},

	async providerToken(c) {
		const now = Date.now();

		if (cachedJwt && cachedJwt.keyId === c.env.apns_key_id && now - cachedJwt.time < JWT_TTL_MS) {
			return cachedJwt.token;
		}

		const header = { alg: 'ES256', kid: c.env.apns_key_id };
		const claims = { iss: c.env.apns_team_id, iat: Math.floor(now / 1000) };
		const unsigned = `${base64Url(JSON.stringify(header))}.${base64Url(JSON.stringify(claims))}`;

		const key = await crypto.subtle.importKey(
			'pkcs8',
			pemToDer(c.env.apns_key),
			{ name: 'ECDSA', namedCurve: 'P-256' },
			false,
			['sign']
		);

		// WebCrypto 输出的是 r||s 原始格式，正好符合 JWS ES256 规范
		const signature = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(unsigned));
		const token = `${unsigned}.${base64Url(signature)}`;

		cachedJwt = { token, time: now, keyId: c.env.apns_key_id };
		return token;
	}
};

function pemToDer(pem) {
	const base64 = pem
		.replace(/-----BEGIN PRIVATE KEY-----/, '')
		.replace(/-----END PRIVATE KEY-----/, '')
		.replace(/\\n/g, '')
		.replace(/\s+/g, '');
	const binary = atob(base64);
	const bytes = new Uint8Array(binary.length);
	for (let i = 0; i < binary.length; i++) {
		bytes[i] = binary.charCodeAt(i);
	}
	return bytes.buffer;
}

function base64Url(input) {
	let binary = '';
	if (typeof input === 'string') {
		binary = String.fromCharCode(...new TextEncoder().encode(input));
	} else {
		binary = String.fromCharCode(...new Uint8Array(input));
	}
	return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export default pushService;
