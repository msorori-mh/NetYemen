-- NetYemen V1 Support, Complaints, and Non-Financial Disputes
-- Task: NY-V1-SUPPORT-DISPUTES-001

CREATE TABLE public.support_cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  case_number BIGINT GENERATED ALWAYS AS IDENTITY UNIQUE,
  case_type TEXT NOT NULL CHECK (case_type IN ('ticket','complaint','dispute')),
  customer_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  network_id UUID REFERENCES public.networks(id) ON DELETE SET NULL,
  package_id UUID REFERENCES public.network_packages(id) ON DELETE SET NULL,
  network_request_id UUID REFERENCES public.network_addition_requests(id) ON DELETE SET NULL,
  category TEXT NOT NULL CHECK (category IN ('network','package','service','account','request','other')),
  priority TEXT NOT NULL DEFAULT 'normal' CHECK (priority IN ('low','normal','high','urgent')),
  subject TEXT NOT NULL CHECK (char_length(trim(subject)) BETWEEN 3 AND 160),
  description TEXT NOT NULL CHECK (char_length(trim(description)) BETWEEN 3 AND 4000),
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','assigned','in_progress','waiting_customer','resolved','closed')),
  assigned_agent_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  resolution TEXT CHECK (resolution IS NULL OR char_length(trim(resolution)) BETWEEN 3 AND 4000),
  resolution_outcome TEXT CHECK (resolution_outcome IS NULL OR resolution_outcome IN ('answered','fixed','not_reproducible','not_supported','refund_recommended')),
  due_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '48 hours'),
  resolved_at TIMESTAMPTZ,
  closed_at TIMESTAMPTZ,
  reopened_count INTEGER NOT NULL DEFAULT 0 CHECK (reopened_count BETWEEN 0 AND 3),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (package_id IS NULL OR network_id IS NOT NULL),
  CHECK ((status IN ('resolved','closed') AND resolution IS NOT NULL AND resolved_at IS NOT NULL)
      OR (status NOT IN ('resolved','closed') AND closed_at IS NULL)),
  CHECK (status <> 'closed' OR closed_at IS NOT NULL)
);

CREATE TABLE public.support_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id UUID NOT NULL REFERENCES public.support_cases(id) ON DELETE CASCADE,
  author_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  body TEXT NOT NULL CHECK (char_length(trim(body)) BETWEEN 1 AND 4000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.support_case_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id UUID NOT NULL REFERENCES public.support_cases(id) ON DELETE CASCADE,
  author_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  body TEXT NOT NULL CHECK (char_length(trim(body)) BETWEEN 1 AND 4000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.support_case_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id UUID NOT NULL REFERENCES public.support_cases(id) ON DELETE CASCADE,
  actor_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  event_type TEXT NOT NULL,
  from_status TEXT,
  to_status TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (octet_length(metadata::text) <= 4096),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX support_cases_customer_idx ON public.support_cases(customer_user_id, created_at DESC);
CREATE INDEX support_cases_queue_idx ON public.support_cases(status, priority, created_at);
CREATE INDEX support_cases_network_idx ON public.support_cases(network_id) WHERE network_id IS NOT NULL;
CREATE INDEX support_messages_case_idx ON public.support_messages(case_id, created_at);
CREATE INDEX support_notes_case_idx ON public.support_case_notes(case_id, created_at);
CREATE INDEX support_events_case_idx ON public.support_case_events(case_id, created_at);

ALTER TABLE public.support_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_case_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_case_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_cases FORCE ROW LEVEL SECURITY;
ALTER TABLE public.support_messages FORCE ROW LEVEL SECURITY;
ALTER TABLE public.support_case_notes FORCE ROW LEVEL SECURITY;
ALTER TABLE public.support_case_events FORCE ROW LEVEL SECURITY;

CREATE FUNCTION public.support_is_active() RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT auth.uid() IS NOT NULL AND EXISTS (SELECT 1 FROM public.profiles WHERE id=auth.uid() AND account_status='active')
$$;

CREATE FUNCTION public.support_owns_network(p_network_id UUID) RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT p_network_id IS NOT NULL AND public.has_platform_role('network_owner') AND EXISTS (
   SELECT 1 FROM public.network_memberships WHERE network_id=p_network_id AND user_id=auth.uid()
     AND membership_role='owner' AND status='active')
$$;

CREATE FUNCTION public.support_can_view_case(p_case_id UUID) RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT public.support_is_active() AND EXISTS (SELECT 1 FROM public.support_cases c WHERE c.id=p_case_id AND (
   c.customer_user_id=auth.uid() OR public.has_platform_role('support_agent') OR
   public.has_platform_role('platform_admin') OR public.support_owns_network(c.network_id)))
$$;

CREATE FUNCTION public.support_staff() RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT public.support_is_active() AND (public.has_platform_role('support_agent') OR public.has_platform_role('platform_admin'))
$$;

CREATE POLICY support_cases_read ON public.support_cases FOR SELECT TO authenticated USING (
 public.support_is_active() AND (customer_user_id=auth.uid() OR public.has_platform_role('support_agent')
 OR public.has_platform_role('platform_admin') OR public.support_owns_network(network_id)));
CREATE POLICY support_messages_read ON public.support_messages FOR SELECT TO authenticated USING (public.support_can_view_case(case_id));
CREATE POLICY support_notes_staff_read ON public.support_case_notes FOR SELECT TO authenticated USING (public.support_staff());
CREATE POLICY support_events_read ON public.support_case_events FOR SELECT TO authenticated USING (public.support_can_view_case(case_id));

CREATE FUNCTION public.support_immutable_row() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN RAISE EXCEPTION 'IMMUTABLE: Support messages, notes, and events cannot be changed.' USING ERRCODE='42501'; END $$;
CREATE TRIGGER support_messages_immutable BEFORE UPDATE OR DELETE ON public.support_messages FOR EACH ROW EXECUTE FUNCTION public.support_immutable_row();
CREATE TRIGGER support_notes_immutable BEFORE UPDATE OR DELETE ON public.support_case_notes FOR EACH ROW EXECUTE FUNCTION public.support_immutable_row();
CREATE TRIGGER support_events_immutable BEFORE UPDATE OR DELETE ON public.support_case_events FOR EACH ROW EXECUTE FUNCTION public.support_immutable_row();

CREATE FUNCTION public.create_support_case(p_case_type TEXT,p_category TEXT,p_priority TEXT,p_subject TEXT,p_description TEXT,
 p_network_id UUID DEFAULT NULL,p_package_id UUID DEFAULT NULL,p_network_request_id UUID DEFAULT NULL) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_id UUID; v_number BIGINT;
BEGIN
 IF NOT public.support_is_active() THEN RAISE EXCEPTION 'FORBIDDEN: Active authentication required.' USING ERRCODE='42501'; END IF;
 IF p_case_type NOT IN ('ticket','complaint','dispute') OR p_category NOT IN ('network','package','service','account','request','other')
    OR p_priority NOT IN ('low','normal','high','urgent') THEN RAISE EXCEPTION 'INVALID_CASE_CLASSIFICATION' USING ERRCODE='22023'; END IF;
 IF p_network_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.networks WHERE id=p_network_id) THEN RAISE EXCEPTION 'INVALID_NETWORK' USING ERRCODE='22023'; END IF;
 IF p_package_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.network_packages WHERE id=p_package_id AND network_id=p_network_id) THEN RAISE EXCEPTION 'INVALID_PACKAGE_REFERENCE' USING ERRCODE='22023'; END IF;
 IF p_network_request_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.network_addition_requests WHERE id=p_network_request_id AND requester_user_id=auth.uid()) THEN RAISE EXCEPTION 'INVALID_REQUEST_REFERENCE' USING ERRCODE='42501'; END IF;
 INSERT INTO public.support_cases(case_type,customer_user_id,network_id,package_id,network_request_id,category,priority,subject,description,due_at)
 VALUES(p_case_type,auth.uid(),p_network_id,p_package_id,p_network_request_id,p_category,p_priority,trim(p_subject),trim(p_description),
 now()+CASE p_priority WHEN 'urgent' THEN interval '4 hours' WHEN 'high' THEN interval '12 hours' WHEN 'normal' THEN interval '48 hours' ELSE interval '72 hours' END)
 RETURNING id,case_number INTO v_id,v_number;
 INSERT INTO public.support_case_events(case_id,actor_user_id,event_type,to_status) VALUES(v_id,auth.uid(),'created','open');
 PERFORM public.record_audit_event('SUPPORT_CASE_CREATED','support_case',v_id::text,'success','CREATE',jsonb_build_object('case_type',p_case_type));
 RETURN jsonb_build_object('id',v_id,'case_number',v_number);
END $$;

CREATE FUNCTION public.add_support_message(p_case_id UUID,p_body TEXT) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_id UUID; v_case public.support_cases%ROWTYPE;
BEGIN
 SELECT * INTO v_case FROM public.support_cases WHERE id=p_case_id;
 IF NOT FOUND OR NOT public.support_can_view_case(p_case_id) THEN RAISE EXCEPTION 'FORBIDDEN_CASE' USING ERRCODE='42501'; END IF;
 IF v_case.status='closed' THEN RAISE EXCEPTION 'CASE_CLOSED' USING ERRCODE='22023'; END IF;
 IF auth.uid()<>v_case.customer_user_id AND NOT public.support_staff() AND NOT public.support_owns_network(v_case.network_id) THEN RAISE EXCEPTION 'FORBIDDEN_REPLY' USING ERRCODE='42501'; END IF;
 INSERT INTO public.support_messages(case_id,author_user_id,body) VALUES(p_case_id,auth.uid(),trim(p_body)) RETURNING id INTO v_id;
 IF auth.uid()=v_case.customer_user_id AND v_case.status='waiting_customer' THEN UPDATE public.support_cases SET status='in_progress',updated_at=now() WHERE id=p_case_id; END IF;
 INSERT INTO public.support_case_events(case_id,actor_user_id,event_type,metadata) VALUES(p_case_id,auth.uid(),'message_added',jsonb_build_object('message_id',v_id));
 RETURN v_id;
END $$;

CREATE FUNCTION public.claim_support_case(p_case_id UUID) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF NOT public.support_staff() THEN RAISE EXCEPTION 'FORBIDDEN_STAFF' USING ERRCODE='42501'; END IF;
 UPDATE public.support_cases SET assigned_agent_id=auth.uid(),status=CASE WHEN status='open' THEN 'assigned' ELSE status END,updated_at=now()
 WHERE id=p_case_id AND status NOT IN ('resolved','closed') AND (assigned_agent_id IS NULL OR assigned_agent_id=auth.uid());
 IF NOT FOUND THEN RAISE EXCEPTION 'CASE_UNAVAILABLE' USING ERRCODE='55000'; END IF;
 INSERT INTO public.support_case_events(case_id,actor_user_id,event_type,to_status) VALUES(p_case_id,auth.uid(),'assigned','assigned');
 PERFORM public.record_audit_event('SUPPORT_CASE_CLAIMED','support_case',p_case_id::text,'success','ASSIGN');
END $$;

CREATE FUNCTION public.update_support_case(p_case_id UUID,p_status TEXT,p_resolution TEXT DEFAULT NULL,p_resolution_outcome TEXT DEFAULT NULL,p_priority TEXT DEFAULT NULL) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_case public.support_cases%ROWTYPE;
BEGIN
 IF NOT public.support_staff() THEN RAISE EXCEPTION 'FORBIDDEN_STAFF' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_case FROM public.support_cases WHERE id=p_case_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'NOT_FOUND' USING ERRCODE='P0002'; END IF;
 IF p_status NOT IN ('assigned','in_progress','waiting_customer','resolved','closed') THEN RAISE EXCEPTION 'INVALID_STATUS' USING ERRCODE='22023'; END IF;
 IF v_case.status='closed' OR (p_status='closed' AND v_case.status<>'resolved') THEN RAISE EXCEPTION 'INVALID_TRANSITION' USING ERRCODE='22023'; END IF;
 IF p_status IN ('resolved','closed') AND coalesce(length(trim(p_resolution)),length(trim(v_case.resolution)),0)<3 THEN RAISE EXCEPTION 'RESOLUTION_REQUIRED' USING ERRCODE='22023'; END IF;
 IF p_resolution_outcome='refund_recommended' AND v_case.case_type<>'dispute' THEN RAISE EXCEPTION 'REFUND_RECOMMENDATION_DISPUTES_ONLY' USING ERRCODE='22023'; END IF;
 UPDATE public.support_cases SET status=p_status,priority=coalesce(p_priority,priority),resolution=coalesce(nullif(trim(p_resolution),''),resolution),
 resolution_outcome=coalesce(p_resolution_outcome,resolution_outcome),resolved_at=CASE WHEN p_status IN ('resolved','closed') THEN coalesce(resolved_at,now()) ELSE resolved_at END,
 closed_at=CASE WHEN p_status='closed' THEN now() ELSE NULL END,updated_at=now() WHERE id=p_case_id;
 INSERT INTO public.support_case_events(case_id,actor_user_id,event_type,from_status,to_status,metadata) VALUES(p_case_id,auth.uid(),'status_changed',v_case.status,p_status,jsonb_build_object('outcome',p_resolution_outcome));
 PERFORM public.record_audit_event('SUPPORT_CASE_STATUS_CHANGED','support_case',p_case_id::text,'success','WORKFLOW',jsonb_build_object('from',v_case.status,'to',p_status));
END $$;

CREATE FUNCTION public.add_support_case_note(p_case_id UUID,p_body TEXT) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_id UUID;
BEGIN
 IF NOT public.support_staff() OR NOT EXISTS(SELECT 1 FROM public.support_cases WHERE id=p_case_id) THEN RAISE EXCEPTION 'FORBIDDEN_STAFF' USING ERRCODE='42501'; END IF;
 INSERT INTO public.support_case_notes(case_id,author_user_id,body) VALUES(p_case_id,auth.uid(),trim(p_body)) RETURNING id INTO v_id;
 INSERT INTO public.support_case_events(case_id,actor_user_id,event_type,metadata) VALUES(p_case_id,auth.uid(),'internal_note_added',jsonb_build_object('note_id',v_id)); RETURN v_id;
END $$;

CREATE FUNCTION public.reopen_support_case(p_case_id UUID,p_reason TEXT) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_case public.support_cases%ROWTYPE;
BEGIN
 SELECT * INTO v_case FROM public.support_cases WHERE id=p_case_id FOR UPDATE;
 IF NOT FOUND OR (auth.uid()<>v_case.customer_user_id AND NOT public.support_staff()) THEN RAISE EXCEPTION 'FORBIDDEN_CASE' USING ERRCODE='42501'; END IF;
 IF v_case.status NOT IN ('resolved','closed') OR v_case.reopened_count>=3 OR v_case.resolved_at < now()-interval '14 days' THEN RAISE EXCEPTION 'REOPEN_NOT_ALLOWED' USING ERRCODE='22023'; END IF;
 UPDATE public.support_cases SET status='open',assigned_agent_id=NULL,closed_at=NULL,reopened_count=reopened_count+1,updated_at=now() WHERE id=p_case_id;
 INSERT INTO public.support_case_events(case_id,actor_user_id,event_type,from_status,to_status,metadata) VALUES(p_case_id,auth.uid(),'reopened',v_case.status,'open',jsonb_build_object('reason',left(trim(p_reason),500)));
 PERFORM public.record_audit_event('SUPPORT_CASE_REOPENED','support_case',p_case_id::text,'success','REOPEN');
END $$;

REVOKE ALL ON public.support_cases,public.support_messages,public.support_case_notes,public.support_case_events FROM PUBLIC,anon;
GRANT SELECT ON public.support_cases,public.support_messages,public.support_case_events TO authenticated;
GRANT SELECT ON public.support_case_notes TO authenticated;
GRANT USAGE,SELECT ON SEQUENCE public.support_cases_case_number_seq TO authenticated;
REVOKE EXECUTE ON FUNCTION public.support_is_active(),public.support_owns_network(UUID),public.support_can_view_case(UUID),public.support_staff() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.support_is_active(),public.support_owns_network(UUID),public.support_can_view_case(UUID),public.support_staff() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.create_support_case(TEXT,TEXT,TEXT,TEXT,TEXT,UUID,UUID,UUID),public.add_support_message(UUID,TEXT),public.claim_support_case(UUID),public.update_support_case(UUID,TEXT,TEXT,TEXT,TEXT),public.add_support_case_note(UUID,TEXT),public.reopen_support_case(UUID,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_support_case(TEXT,TEXT,TEXT,TEXT,TEXT,UUID,UUID,UUID),public.add_support_message(UUID,TEXT),public.claim_support_case(UUID),public.update_support_case(UUID,TEXT,TEXT,TEXT,TEXT),public.add_support_case_note(UUID,TEXT),public.reopen_support_case(UUID,TEXT) TO authenticated;
