-- TEST_ONLY NetYemen V1 local pilot seed. Never use against a remote project.
-- All identities, references, amounts, and names below are synthetic.

INSERT INTO auth.users (id,email) VALUES
 ('10000000-0000-4000-8000-000000000001','customer1@pilot.netyemen.test'),
 ('10000000-0000-4000-8000-000000000002','customer2@pilot.netyemen.test'),
 ('20000000-0000-4000-8000-000000000001','owner@pilot.netyemen.test'),
 ('20000000-0000-4000-8000-000000000002','operator@pilot.netyemen.test'),
 ('30000000-0000-4000-8000-000000000001','finance@pilot.netyemen.test'),
 ('30000000-0000-4000-8000-000000000002','support@pilot.netyemen.test'),
 ('40000000-0000-4000-8000-000000000001','admin@pilot.netyemen.test'),
 ('40000000-0000-4000-8000-000000000002','auditor@pilot.netyemen.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles(id,full_name,account_status) VALUES
 ('10000000-0000-4000-8000-000000000001','TEST_ONLY عميل تجريبي 1','active'),
 ('10000000-0000-4000-8000-000000000002','TEST_ONLY عميل تجريبي 2','active'),
 ('20000000-0000-4000-8000-000000000001','TEST_ONLY مالك شبكة','active'),
 ('20000000-0000-4000-8000-000000000002','TEST_ONLY مشغل شبكة','active'),
 ('30000000-0000-4000-8000-000000000001','TEST_ONLY مسؤول مالية','active'),
 ('30000000-0000-4000-8000-000000000002','TEST_ONLY مسؤول دعم','active'),
 ('40000000-0000-4000-8000-000000000001','TEST_ONLY مدير منصة','active'),
 ('40000000-0000-4000-8000-000000000002','TEST_ONLY مدقق قراءة فقط','active')
ON CONFLICT (id) DO UPDATE SET full_name=EXCLUDED.full_name,account_status='active';

INSERT INTO public.user_roles(user_id,role) VALUES
 ('10000000-0000-4000-8000-000000000001','customer'),
 ('10000000-0000-4000-8000-000000000002','customer'),
 ('20000000-0000-4000-8000-000000000001','network_owner'),
 ('20000000-0000-4000-8000-000000000002','network_operator'),
 ('30000000-0000-4000-8000-000000000001','finance_officer'),
 ('30000000-0000-4000-8000-000000000002','support_agent'),
 ('40000000-0000-4000-8000-000000000001','platform_admin'),
 ('40000000-0000-4000-8000-000000000002','system_auditor')
ON CONFLICT (user_id,role) DO NOTHING;

INSERT INTO public.networks(id,commercial_name,description,governorate,city,district,status,verification_status,created_by,approved_by,approved_at) VALUES
 ('50000000-0000-4000-8000-000000000001','TEST_ONLY شبكة صنعاء التجريبية','بيانات محلية تجريبية فقط','صنعاء','صنعاء','حدة','active','verified','20000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001',now()),
 ('50000000-0000-4000-8000-000000000002','TEST_ONLY شبكة إب التجريبية','بيانات محلية تجريبية فقط','إب','إب',NULL,'active','verified','20000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001',now())
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.network_memberships(network_id,user_id,membership_role,status,created_by) VALUES
 ('50000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','owner','active','40000000-0000-4000-8000-000000000001'),
 ('50000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002','operator','active','20000000-0000-4000-8000-000000000001'),
 ('50000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000001','owner','active','40000000-0000-4000-8000-000000000001')
ON CONFLICT (network_id,user_id) DO NOTHING;

SELECT set_config('request.jwt.claim.sub','40000000-0000-4000-8000-000000000001',false);
SELECT set_config('request.jwt.claims','{"sub":"40000000-0000-4000-8000-000000000001","role":"authenticated"}',false);

INSERT INTO public.network_ssid_aliases(id,network_id,ssid_display,ssid_normalized,status,verified_at,verified_by) VALUES
 ('51000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001','NY-PILOT-SANAA','ny-pilot-sanaa','active',now(),'40000000-0000-4000-8000-000000000001'),
 ('51000000-0000-4000-8000-000000000002','50000000-0000-4000-8000-000000000002','NY-PILOT-IBB','ny-pilot-ibb','active',now(),'40000000-0000-4000-8000-000000000001')
ON CONFLICT (id) DO NOTHING;

SELECT set_config('request.jwt.claim.sub','',false);
SELECT set_config('request.jwt.claims','{}',false);

INSERT INTO public.network_packages(id,network_id,name,description,price,duration_value,duration_unit,package_type,status,is_public,created_by) VALUES
 ('60000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001','TEST_ONLY باقة يوم','قيمة تجريبية 1000 ريال يمني',1000,1,'day','time','active',true,'20000000-0000-4000-8000-000000000001'),
 ('60000000-0000-4000-8000-000000000002','50000000-0000-4000-8000-000000000001','TEST_ONLY باقة أسبوع','قيمة تجريبية 3000 ريال يمني',3000,1,'week','time','active',true,'20000000-0000-4000-8000-000000000001'),
 ('60000000-0000-4000-8000-000000000003','50000000-0000-4000-8000-000000000002','TEST_ONLY آخر وحدة','باقة سباق مخزون محلي',500,1,'day','time','active',true,'20000000-0000-4000-8000-000000000001')
ON CONFLICT (id) DO NOTHING;

UPDATE public.package_inventory_balances SET total_units=25,available_units=25,is_available=true
WHERE package_id='60000000-0000-4000-8000-000000000001';
UPDATE public.package_inventory_balances SET total_units=10,available_units=10,is_available=true
WHERE package_id='60000000-0000-4000-8000-000000000002';
UPDATE public.package_inventory_balances SET total_units=1,available_units=1,is_available=true
WHERE package_id='60000000-0000-4000-8000-000000000003';

INSERT INTO public.customer_wallet_ledger(user_id,entry_type,amount,balance_after,reference_type,idempotency_key,actor_user_id,reason_code,metadata)
VALUES
 ('10000000-0000-4000-8000-000000000001','CREDIT',10000,10000,'ADJUSTMENT','70000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001','TEST_ONLY_PILOT_OPENING_BALANCE','{"test_only":true}'),
 ('10000000-0000-4000-8000-000000000002','CREDIT',2000,2000,'ADJUSTMENT','70000000-0000-4000-8000-000000000002','40000000-0000-4000-8000-000000000001','TEST_ONLY_PILOT_OPENING_BALANCE','{"test_only":true}')
ON CONFLICT (user_id,idempotency_key) DO NOTHING;

INSERT INTO public.wallet_deposit_requests(id,user_id,amount,reference_number,status,idempotency_key)
VALUES('71000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001',5000,'TEST_ONLY-LOCAL-DEP-001','pending','71000000-0000-4000-8000-000000000002')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.support_cases(id,case_type,customer_user_id,network_id,package_id,category,priority,subject,description)
VALUES('80000000-0000-4000-8000-000000000001','ticket','10000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000001','service','normal','TEST_ONLY استفسار تجريبي','حالة دعم محلية تجريبية لا تخص مستخدماً حقيقياً')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.support_case_events(case_id,actor_user_id,event_type,to_status,metadata)
VALUES('80000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','created','open','{"test_only":true}')
ON CONFLICT DO NOTHING;
