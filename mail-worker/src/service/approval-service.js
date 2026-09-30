import orm from '../entity/orm';
import email from '../entity/email';
import accountService from './account-service';
import { emailConst, isDel } from '../const/entity-const';
import { toUtc } from '../utils/date-uitil';

function escapeHtml(str) {
	return String(str)
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;')
		.replace(/'/g, '&#39;');
}

const approvalService = {

	// 有新用户待审核时，直接在管理员收件箱写入一封站内通知信
	async notifyAdmin(c, regEmail) {

		try {

			const adminEmail = c.env.admin;

			if (!adminEmail) return;

			const adminAccount = await accountService.selectByEmailIncludeDel(c, adminEmail);

			if (!adminAccount || adminAccount.isDel === isDel.DELETE) return;

			const time = toUtc().tz('Asia/Taipei').format('YYYY-MM-DD HH:mm');
			const origin = c.req?.url ? new URL(c.req.url).origin : '';
			const safeEmail = escapeHtml(regEmail);

			const subject = `[註冊審核] ${regEmail} 申請建立信箱`;

			const text = `有新使用者申請註冊，需要你批准：\n\n信箱：${regEmail}\n申請時間：${time} (UTC+8)\n\n請到「使用者管理」篩選「待審核」進行批准或拒絕。${origin ? '\n' + origin + '/all-users' : ''}`;

			const content = `<div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; font-size: 14px; color: #1f2328; line-height: 1.6;">
<p>有新使用者申請註冊，需要你批准：</p>
<table style="border-collapse: collapse; margin: 12px 0;">
<tr><td style="padding: 4px 16px 4px 0; color: #656d76;">信箱</td><td style="padding: 4px 0;"><b>${safeEmail}</b></td></tr>
<tr><td style="padding: 4px 16px 4px 0; color: #656d76;">申請時間</td><td style="padding: 4px 0;">${time} (UTC+8)</td></tr>
</table>
<p>請到「使用者管理」篩選「待審核」進行批准或拒絕。</p>
${origin ? `<p><a href="${origin}/all-users" style="color: #0969da;">前往使用者管理</a></p>` : ''}
</div>`;

			await orm(c).insert(email).values({
				sendEmail: adminEmail,
				name: 'Genius Mail',
				accountId: adminAccount.accountId,
				userId: adminAccount.userId,
				subject,
				text,
				content,
				recipient: JSON.stringify([{ address: adminEmail, name: '' }]),
				toEmail: adminEmail,
				toName: adminAccount.name || '',
				type: emailConst.type.RECEIVE,
				status: emailConst.status.RECEIVE,
				isDel: isDel.NORMAL
			}).run();

		} catch (e) {
			console.error('注册审核通知失败:', e);
		}
	}

};

export default approvalService;
