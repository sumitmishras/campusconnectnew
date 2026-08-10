-- =====================================================================
-- 0011  Reference data: Chandigarh University, programs, badges, tags
-- =====================================================================
-- Mirrors lib/core/services/cu_identity.dart. Once this lands, the Dart
-- `_programs` map can be deleted and the picker fed from the DB, so
-- adding a course stops being an app release.
-- =====================================================================

insert into public.universities (slug, name, short_name, email_domain, uid_pattern)
values ('cu', 'Chandigarh University', 'CU', 'cuchd.in', '^(\d{2})([a-z]{3})(\d{3,5})$')
on conflict (slug) do update set
  name = excluded.name,
  uid_pattern = excluded.uid_pattern;


insert into public.programs (university_id, code, department, course, duration_years)
select u.id, v.code, v.department, v.course, v.years
from public.universities u,
(values
  ('bcs', 'Computer Science',       'B.E. CSE',        4),
  ('bai', 'AI & ML',                'B.E. AI & ML',    4),
  ('bit', 'Information Technology', 'B.E. IT',         4),
  ('bec', 'Electronics & Comm.',    'B.E. ECE',        4),
  ('bee', 'Electrical',             'B.E. EE',         4),
  ('bme', 'Mechanical',             'B.E. ME',         4),
  ('bcv', 'Civil',                  'B.E. CE',         4),
  ('bce', 'Civil',                  'B.E. CE',         4),
  ('bca', 'Computer Applications',  'BCA',             3),
  ('mca', 'Computer Applications',  'MCA',             2),
  ('mcs', 'Computer Science',       'M.E. CSE',        2),
  ('bba', 'Management',             'BBA',             3),
  ('mba', 'Management',             'MBA',             2),
  ('bcm', 'Commerce',               'B.Com',           3),
  ('bsc', 'Sciences',               'B.Sc',            3),
  ('msc', 'Sciences',               'M.Sc',            2),
  ('bph', 'Pharmacy',               'B.Pharm',         4),
  ('bla', 'Law',                    'BA LLB',          5),
  ('bhm', 'Hotel Management',       'BHMCT',           4),
  ('bjm', 'Journalism',             'BA JMC',          3),
  ('bar', 'Architecture',           'B.Arch',          5),
  ('bag', 'Agriculture',            'B.Sc Agriculture',4)
) as v(code, department, course, years)
where u.slug = 'cu'
on conflict (university_id, code) do update set
  department = excluded.department,
  course     = excluded.course;


insert into public.badges (slug, label, description, icon, color) values
  ('admin',            'Admin',            'Campus Connect administrator',        'shield',      '#DC2626'),
  ('moderator',        'Moderator',        'Reviews reports and moderates content','shield-check','#EA580C'),
  ('campus_ambassador','Campus Ambassador','Official student ambassador',          'award',       '#7C3AED'),
  ('club_rep',         'Club Representative','Runs a registered club',             'users',       '#2563EB'),
  ('early_adopter',    'Early Adopter',    'Joined in the first semester',         'sparkles',    '#0891B2'),
  ('helpful',          'Helpful',          'Consistently helps other students',    'heart-handshake','#16A34A'),
  ('event_host',       'Event Host',       'Has hosted a campus event',            'calendar',    '#DB2777'),
  ('top_contributor',  'Top Contributor',  'Among the most active students',       'trending-up', '#CA8A04')
on conflict (slug) do update set label = excluded.label, description = excluded.description;


insert into public.tags (slug, label, category) values
  ('coding','Coding','interest'), ('design','Design','interest'),
  ('photography','Photography','interest'), ('music','Music','interest'),
  ('dance','Dance','interest'), ('sports','Sports','interest'),
  ('cricket','Cricket','interest'), ('football','Football','interest'),
  ('gaming','Gaming','interest'), ('reading','Reading','interest'),
  ('writing','Writing','interest'), ('travel','Travel','interest'),
  ('startups','Startups','interest'), ('finance','Finance','interest'),
  ('robotics','Robotics','interest'), ('ai-ml','AI / ML','interest'),
  ('cybersecurity','Cybersecurity','interest'), ('debate','Debate','interest'),
  ('theatre','Theatre','interest'), ('volunteering','Volunteering','interest'),

  ('hindi','Hindi','language'), ('english','English','language'),
  ('punjabi','Punjabi','language'), ('tamil','Tamil','language'),
  ('telugu','Telugu','language'), ('bengali','Bengali','language'),
  ('marathi','Marathi','language'), ('kannada','Kannada','language'),
  ('malayalam','Malayalam','language'), ('gujarati','Gujarati','language'),
  ('urdu','Urdu','language'), ('assamese','Assamese','language'),

  ('study-partner','Study Partner','looking_for'),
  ('project-teammate','Project Teammate','looking_for'),
  ('hackathon-team','Hackathon Team','looking_for'),
  ('mentor','Mentor','looking_for'),
  ('mentee','Mentee','looking_for'),
  ('friends','Friends','looking_for'),
  ('gym-buddy','Gym Buddy','looking_for'),
  ('roommate','Roommate','looking_for'),
  ('startup-cofounder','Startup Co-founder','looking_for'),
  ('placement-prep','Placement Prep','looking_for')
on conflict (slug) do update set label = excluded.label;


-- ---------------------------------------------------------------------
-- Department communities
-- ---------------------------------------------------------------------
-- One auto-join hub per department, each with its conversation created
-- in the same transaction so the pair can never exist half-formed.
do $$
declare
  v_uni  uuid;
  v_dept text;
  v_conv uuid;
  v_slug citext;
begin
  select id into v_uni from public.universities where slug = 'cu';

  for v_dept in select distinct department from public.programs where university_id = v_uni order by 1
  loop
    v_slug := regexp_replace(lower(v_dept), '[^a-z0-9]+', '-', 'g');
    v_slug := trim(both '-' from v_slug);

    if exists (select 1 from public.communities where university_id = v_uni and slug = v_slug) then
      continue;
    end if;

    insert into public.conversations (university_id, type, source_type, source_id, title, description)
    values (v_uni, 'group', 'community', public.uuid_generate_v7(), v_dept,
            v_dept || ' students at Chandigarh University')
    returning id into v_conv;

    insert into public.communities (
      id, university_id, conversation_id, slug, name, description,
      is_department, is_auto_join
    ) values (
      (select source_id from public.conversations where id = v_conv),
      v_uni, v_conv, v_slug, v_dept,
      'Everyone studying ' || v_dept || ' at CU.', true, true
    );
  end loop;
end $$;


-- Add new students to their department community automatically.
create or replace function public.tg_autojoin_department_community()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_conv uuid;
begin
  if new.department is null or new.department = '' then
    return null;
  end if;
  if tg_op = 'UPDATE' and new.department = old.department then
    return null;
  end if;

  select c.conversation_id into v_conv
  from public.communities c
  where c.university_id = new.university_id
    and c.name = new.department
    and c.is_auto_join;

  if v_conv is null then
    return null;
  end if;

  insert into public.conversation_members (conversation_id, user_id, visible_from_seq)
  select v_conv, new.id, coalesce(last_seq, 0) from public.conversations where id = v_conv
  on conflict (conversation_id, user_id) do nothing;

  return null;
end;
$$;

create or replace trigger autojoin_department_community
  after insert or update of department on public.profiles
  for each row execute function public.tg_autojoin_department_community();
