import s3Service from './s3-service';
import settingService from './setting-service';
import kvObjService from './kv-obj-service';

// HTTP 标头只能是 Latin-1，中文等文件名需转成 RFC 5987 格式
function safeDisposition(value) {

	if (!value || /^[\x20-\x7e]*$/.test(value)) {
		return value || null;
	}

	const match = value.match(/^\s*(\w+)\s*;\s*filename=(.*)$/i);

	if (!match) {
		return null;
	}

	return `${match[1]}; filename*=UTF-8''${encodeURIComponent(match[2].trim())}`;
}

const r2Service = {

	async storageType(c) {

		const setting = await settingService.query(c);
		const { bucket, endpoint, s3AccessKey, s3SecretKey } = setting;

		if (!!(bucket && endpoint && s3AccessKey && s3SecretKey)) {
			return 'S3';
		}

		if (c.env.r2) {
			return 'R2';
		}

		return 'KV';
	},

	async putObj(c, key, content, metadata) {

		const storageType = await this.storageType(c);

		if (storageType === 'KV') {
			await kvObjService.putObj(c, key, content, metadata);
		}

		if (storageType === 'R2') {
			await c.env.r2.put(key, content, {
				httpMetadata: { ...metadata }
			});
		}

		if (storageType === 'S3') {
			await s3Service.putObj(c, key, content, metadata);
		}

	},

	async getObj(c, key) {
		const storageType = await this.storageType(c);

		if (storageType === 'KV') {
			return await kvObjService.getObj(c, key);
		}

		if (storageType === 'R2') {
			return await c.env.r2.get(key);
		}

		if (storageType === 'S3') {
			return await s3Service.getObj(c, key);
		}
	},

	async toObjResp(c, key) {

		const obj = await this.getObj(c, key);

		if (!obj) {
			return new Response('Not Found', { status: 404 });
		}

		if (obj instanceof Response) {
			return obj;
		}

		return new Response(obj.body, {
			headers: {
				'Content-Type': obj.httpMetadata?.contentType || 'application/octet-stream',
				'Content-Disposition': safeDisposition(obj.httpMetadata?.contentDisposition),
				'Cache-Control': obj.httpMetadata?.cacheControl || null
			}
		});
	},

	async delete(c, key) {

		const storageType = await this.storageType(c);

		if (storageType === 'KV') {
			await kvObjService.deleteObj(c, key);
		}

		if (storageType === 'R2') {
			await c.env.r2.delete(key);
		}

		if (storageType === 'S3'){
			await s3Service.deleteObj(c, key);
		}

	}

};
export default r2Service;
