/// Compatibility export surface for code that has not migrated to feature-
/// owned provider imports yet.
///
/// Runtime application code must import the owning core or feature module
/// directly. No provider may be declared in this legacy facade.
library;

export '../core/config/app_config_provider.dart' show appConfigProvider;
export '../core/providers/supabase_service_provider.dart'
    show supabaseServiceProvider;
export '../features/auth/presentation/customer_session_providers.dart'
    show authStateProvider, currentUserProvider, currentUserRolesProvider;
export '../features/profile/presentation/customer_profile_providers.dart'
    show userProfileProvider;
