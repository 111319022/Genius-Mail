import app from '../hono/hono';
import pushService from '../service/push-service';
import result from '../model/result';
import userContext from '../security/user-context';

app.post('/push/register', async (c) => {
	await pushService.register(c, await c.req.json(), userContext.getUserId(c));
	return c.json(result.ok());
});

app.delete('/push/unregister', async (c) => {
	await pushService.unregister(c, c.req.query(), userContext.getUserId(c));
	return c.json(result.ok());
});

app.get('/push/status', async (c) => {
	const devices = await pushService.devices(c, userContext.getUserId(c));
	return c.json(result.ok({
		configured: pushService.isConfigured(c),
		devices: devices.map(({ env, name, updateTime, token }) => ({ env, name, updateTime, tokenSuffix: token.slice(-8) }))
	}));
});

app.post('/push/test', async (c) => {
	const results = await pushService.sendTest(c, userContext.getUserId(c));
	return c.json(result.ok(results));
});
