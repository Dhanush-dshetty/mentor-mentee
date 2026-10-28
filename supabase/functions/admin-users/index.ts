// Admin-only account management. Uses the service role key, which never reaches the browser.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

  const jwt = (req.headers.get('Authorization') || '').replace('Bearer ', '');
  const { data: { user } } = await admin.auth.getUser(jwt);
  const { data: me } = await admin.from('profiles').select('role,disabled').eq('id', user?.id ?? '').maybeSingle();
  if (!me || me.role !== 'admin' || me.disabled) return json({ error: 'Admins only.' }, 403);

  const b = await req.json();
  try {
    if (b.action === 'create') {
      if (!['mentor', 'mentee'].includes(b.role) || !b.name || !b.email || (b.password || '').length < 6)
        return json({ error: 'Name, email and a password of 6+ characters are required.' }, 400);
      const { data, error } = await admin.auth.admin.createUser({ email: b.email, password: b.password, email_confirm: true });
      if (error) return json({ error: error.message }, 400);
      const id = data.user.id;
      const p = await admin.from('profiles').insert({
        id, role: b.role, name: b.name, email: b.email, dept: b.dept,
        title: b.role === 'mentor' ? 'Faculty, ' + b.dept : null,
        hours: b.role === 'mentor' ? 'By appointment' : null });
      const m = !p.error && b.role === 'mentee' ? await admin.from('mentees').insert({ id, mentor_id: b.mentor_id || null }) : null;
      if (p.error || m?.error) { await admin.auth.admin.deleteUser(id); return json({ error: (p.error || m!.error)!.message }, 400); }
      return json({ ok: true, id });
    }
    if (b.action === 'disable') {
      if (b.id === user!.id) return json({ error: 'You cannot disable your own account.' }, 400);
      await admin.from('profiles').update({ disabled: !!b.off }).eq('id', b.id);
      await admin.auth.admin.updateUserById(b.id, { ban_duration: b.off ? '876000h' : 'none' });
      return json({ ok: true });
    }
    if (b.action === 'reset') {
      if ((b.password || '').length < 6) return json({ error: 'Password too short.' }, 400);
      const { error } = await admin.auth.admin.updateUserById(b.id, { password: b.password });
      return error ? json({ error: error.message }, 400) : json({ ok: true });
    }
    return json({ error: 'Unknown action.' }, 400);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
