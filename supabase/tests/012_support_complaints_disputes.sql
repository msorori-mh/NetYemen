-- NY-V1-SUPPORT-DISPUTES-001 positive and negative authorization suite
BEGIN;
DO $$
DECLARE
 u1 UUID:='91000000-0000-4000-a000-000000000001'; u2 UUID:='91000000-0000-4000-a000-000000000002';
 agent UUID:='91000000-0000-4000-a000-000000000003'; owner1 UUID:='91000000-0000-4000-a000-000000000004';
 owner2 UUID:='91000000-0000-4000-a000-000000000005'; admin UUID:='91000000-0000-4000-a000-000000000006';
 net1 UUID:='92000000-0000-4000-a000-000000000001'; net2 UUID:='92000000-0000-4000-a000-000000000002';
 c1 UUID; c2 UUID; result JSONB; n BIGINT; denied BOOLEAN;
BEGIN
 INSERT INTO auth.users(id,email) VALUES(u1,'support-u1@test.local'),(u2,'support-u2@test.local'),(agent,'support-agent@test.local'),(owner1,'support-owner1@test.local'),(owner2,'support-owner2@test.local'),(admin,'support-admin@test.local');
 INSERT INTO public.profiles(id,full_name,account_status) VALUES(u1,'U1','active'),(u2,'U2','active'),(agent,'Agent','active'),(owner1,'Owner 1','active'),(owner2,'Owner 2','active'),(admin,'Admin','active') ON CONFLICT(id) DO UPDATE SET full_name=excluded.full_name,account_status='active';
 INSERT INTO public.user_roles(user_id,role) VALUES(agent,'support_agent'),(owner1,'network_owner'),(owner2,'network_owner'),(admin,'platform_admin') ON CONFLICT DO NOTHING;
 INSERT INTO public.networks(id,commercial_name,status,verification_status,approved_by,approved_at,created_by) VALUES
 (net1,'Support Network 1','active','verified',admin,now(),owner1),(net2,'Support Network 2','active','verified',admin,now(),owner2);
 INSERT INTO public.network_memberships(network_id,user_id,membership_role,status,created_by) VALUES(net1,owner1,'owner','active',admin),(net2,owner2,'owner','active',admin);

 SET LOCAL ROLE authenticated; PERFORM set_config('request.jwt.claim.sub',u1::text,true); PERFORM set_config('request.jwt.claims',json_build_object('sub',u1,'role','authenticated')::text,true);
 result:=public.create_support_case('dispute','network','high','انقطاع الخدمة','تفاصيل نزاع غير مالي',net1,NULL,NULL); c1:=(result->>'id')::uuid;
 IF NOT EXISTS(SELECT 1 FROM public.support_cases WHERE id=c1 AND customer_user_id=u1 AND due_at<=created_at+interval '12 hours 1 minute') THEN RAISE EXCEPTION 'POS-01 create/own/SLA failed'; END IF;
 PERFORM public.add_support_message(c1,'رسالة العميل');
 IF (SELECT count(*) FROM public.support_messages WHERE case_id=c1)<>1 THEN RAISE EXCEPTION 'POS-02 customer reply failed'; END IF;

 PERFORM set_config('request.jwt.claim.sub',u2::text,true); PERFORM set_config('request.jwt.claims',json_build_object('sub',u2,'role','authenticated')::text,true);
 denied:=false; BEGIN PERFORM 1 FROM public.support_cases WHERE id=c1; IF FOUND THEN RAISE EXCEPTION 'visible'; END IF; EXCEPTION WHEN OTHERS THEN denied:=true; END;
 IF (SELECT count(*) FROM public.support_cases WHERE id=c1)<>0 THEN RAISE EXCEPTION 'NEG-01 cross-customer read'; END IF;
 denied:=false; BEGIN PERFORM public.add_support_message(c1,'اختراق'); EXCEPTION WHEN OTHERS THEN denied:=true; END; IF NOT denied THEN RAISE EXCEPTION 'NEG-02 cross-customer reply'; END IF;
 denied:=false; BEGIN PERFORM public.claim_support_case(c1); EXCEPTION WHEN OTHERS THEN denied:=true; END; IF NOT denied THEN RAISE EXCEPTION 'NEG-03 customer claim'; END IF;
 denied:=false; BEGIN PERFORM public.update_support_case(c1,'resolved','حل مزور','fixed'); EXCEPTION WHEN OTHERS THEN denied:=true; END; IF NOT denied THEN RAISE EXCEPTION 'NEG-04 customer resolve'; END IF;

 PERFORM set_config('request.jwt.claim.sub',owner2::text,true); PERFORM set_config('request.jwt.claims',json_build_object('sub',owner2,'role','authenticated')::text,true);
 IF (SELECT count(*) FROM public.support_cases WHERE id=c1)<>0 THEN RAISE EXCEPTION 'NEG-05 unrelated owner read'; END IF;
 PERFORM set_config('request.jwt.claim.sub',owner1::text,true); PERFORM set_config('request.jwt.claims',json_build_object('sub',owner1,'role','authenticated')::text,true);
 IF (SELECT count(*) FROM public.support_cases WHERE id=c1)<>1 THEN RAISE EXCEPTION 'POS-03 related owner read'; END IF;
 PERFORM public.add_support_message(c1,'رد مالك الشبكة');
 IF (SELECT count(*) FROM public.support_case_notes WHERE case_id=c1)<>0 THEN RAISE EXCEPTION 'NEG-06 owner internal notes'; END IF;

 PERFORM set_config('request.jwt.claim.sub',agent::text,true); PERFORM set_config('request.jwt.claims',json_build_object('sub',agent,'role','authenticated')::text,true);
 PERFORM public.claim_support_case(c1); PERFORM public.update_support_case(c1,'in_progress'); PERFORM public.add_support_case_note(c1,'ملاحظة داخلية');
 PERFORM public.update_support_case(c1,'resolved','يوصى بمراجعة الاسترداد من المالية','refund_recommended');
 IF NOT EXISTS(SELECT 1 FROM public.support_cases WHERE id=c1 AND status='resolved' AND resolution_outcome='refund_recommended') THEN RAISE EXCEPTION 'POS-04 agent lifecycle'; END IF;
 denied:=false; BEGIN UPDATE public.support_case_events SET event_type='tamper' WHERE case_id=c1; EXCEPTION WHEN OTHERS THEN denied:=true; END; IF NOT denied THEN RAISE EXCEPTION 'NEG-07 event mutation'; END IF;
 denied:=false; BEGIN UPDATE public.support_messages SET body='tamper' WHERE case_id=c1; EXCEPTION WHEN OTHERS THEN denied:=true; END; IF NOT denied THEN RAISE EXCEPTION 'NEG-08 message mutation'; END IF;

 PERFORM set_config('request.jwt.claim.sub',u1::text,true); PERFORM set_config('request.jwt.claims',json_build_object('sub',u1,'role','authenticated')::text,true);
 PERFORM public.reopen_support_case(c1,'المشكلة مستمرة');
 IF NOT EXISTS(SELECT 1 FROM public.support_cases WHERE id=c1 AND status='open' AND reopened_count=1) THEN RAISE EXCEPTION 'POS-05 reopen'; END IF;
 IF (SELECT count(*) FROM public.support_case_notes WHERE case_id=c1)<>0 THEN RAISE EXCEPTION 'NEG-09 customer internal-note visibility'; END IF;

 result:=public.create_support_case('ticket','service','normal','تذكرة عادية','تفاصيل تذكرة عادية'); c2:=(result->>'id')::uuid;
 PERFORM set_config('request.jwt.claim.sub',agent::text,true); PERFORM set_config('request.jwt.claims',json_build_object('sub',agent,'role','authenticated')::text,true);
 PERFORM public.claim_support_case(c2);
 denied:=false; BEGIN PERFORM public.update_support_case(c2,'resolved','تمت المعالجة','refund_recommended'); EXCEPTION WHEN OTHERS THEN denied:=true; END; IF NOT denied THEN RAISE EXCEPTION 'NEG-10 refund recommendation on ticket'; END IF;
 denied:=false; BEGIN PERFORM public.update_support_case(c2,'closed','إغلاق مباشر','answered'); EXCEPTION WHEN OTHERS THEN denied:=true; END; IF NOT denied THEN RAISE EXCEPTION 'NEG-11 close before resolved'; END IF;

 PERFORM set_config('request.jwt.claim.sub',admin::text,true); PERFORM set_config('request.jwt.claims',json_build_object('sub',admin,'role','authenticated')::text,true);
 SELECT count(*) INTO n FROM public.support_cases WHERE id IN(c1,c2); IF n<>2 THEN RAISE EXCEPTION 'POS-06 admin oversight'; END IF;
 RAISE NOTICE 'SUCCESS: Support/complaints/disputes authorization tests passed (6 positive, 11 negative).';
END $$;
ROLLBACK;
