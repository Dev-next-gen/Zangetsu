import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:watch_app/core/profiles/viewer_profile.dart';
import 'package:watch_app/core/supabase/auth_user.dart';
import 'package:watch_app/features/auth/auth_cubit.dart';
import 'package:watch_app/features/profiles/viewer_profile_editor_screen.dart';

Widget _profileEditorHost(
  ValueChanged<ProfileEditorResult?> onResult, {
  ViewerProfile editingProfile = profile,
}) => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: TextButton(
        onPressed: () {
          Navigator.of(context)
              .push<ProfileEditorResult>(
                MaterialPageRoute<ProfileEditorResult>(
                  builder: (_) =>
                      ViewerProfileEditorScreen(profile: editingProfile),
                ),
              )
              .then(onResult);
        },
        child: const Text('Open editor'),
      ),
    ),
  ),
);

Widget _profileStoreEditorHost(
  ViewerProfileStore store, {
  ViewerProfile editingProfile = profile,
  ValueChanged<Future<void>>? onOpened,
}) => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: TextButton(
        onPressed: () {
          final future = openViewerProfileEditor(
            context,
            store,
            profile: editingProfile,
          );
          onOpened?.call(future);
        },
        child: const Text('Open editor'),
      ),
    ),
  ),
);

const profile = ViewerProfile(id: 'default', name: 'Home', avatar: 1);

void main() {
  testWidgets('editor is a full page and returns the saved values', (
    tester,
  ) async {
    ProfileEditorResult? result;
    await tester.pumpWidget(_profileEditorHost((value) => result = value));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Edit profile'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Evening');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(result?.name, 'Evening');
    expect(result?.avatar, 1);
    expect(result?.isKids, isFalse);
  });

  testWidgets('cancel returns no profile changes', (tester) async {
    ProfileEditorResult? result;
    await tester.pumpWidget(_profileEditorHost((value) => result = value));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Discard');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets('choosing a built-in avatar replaces a deleted photo', (
    tester,
  ) async {
    final profiles = _RecordingProfileStore();
    const photoProfile = ViewerProfile(
      id: 'photo-profile',
      name: 'Photo profile',
      photoUrl: 'https://cdn.example/deleted.jpg',
    );
    profiles.visibleProfiles = [
      photoProfile,
      const ViewerProfile(
        id: 'shared-photo-profile',
        name: 'Shared photo profile',
        photoUrl: 'https://cdn.example/deleted.jpg',
      ),
    ];
    profiles.synced = true;
    Future<void>? editorFinished;
    await tester.pumpWidget(
      _profileStoreEditorHost(
        profiles,
        editingProfile: photoProfile,
        onOpened: (future) => editorFinished = future,
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('profile-editor-avatar-4')));
    await tester.pump();

    expect(find.byType(Image), findsNothing);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await editorFinished!;

    expect(profiles.updatedAvatar, 4);
    expect(profiles.updatedPhotoUrl, isNull);
    expect(profiles.clearedPhotoUrl, isTrue);
  });

  testWidgets('photo picker keeps a sharp bounded source', (tester) async {
    const channel = MethodChannel('plugins.flutter.io/image_picker');
    MethodCall? pickedCall;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      pickedCall = call;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(_profileEditorHost((_) {}));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose photo'));
    await tester.pumpAndSettle();
    expect(find.text('Animated GIF file'), findsOneWidget);
    await tester.tap(find.text('Photo from gallery'));
    await tester.pump();

    expect(pickedCall?.method, 'pickImage');
    expect(pickedCall?.arguments['maxWidth'], 768.0);
    expect(pickedCall?.arguments['maxHeight'], 768.0);
    expect(pickedCall?.arguments['imageQuality'], 100);
  });

  testWidgets('edit saves the entered name, avatar, and kids setting', (
    tester,
  ) async {
    final store = _RecordingProfileStore();
    await tester.pumpWidget(_profileStoreEditorHost(store));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Evening');
    await tester.tap(find.byKey(const ValueKey('profile-editor-avatar-4')));
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(store.renamedTo, 'Evening');
    expect(store.updatedAvatar, 4);
    expect(store.updatedIsKids, isTrue);
  });

  testWidgets('renaming Home updates the sign-in account name', (tester) async {
    final store = _RecordingProfileStore();
    final auth = _RecordingAuthCubit();
    GetIt.instance.registerSingleton<AuthCubit>(auth);
    addTearDown(() async {
      await GetIt.instance.unregister<AuthCubit>();
      await auth.close();
    });
    await tester.pumpWidget(_profileStoreEditorHost(store));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Evening');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(auth.renamedTo, 'Evening');
    expect(store.renamedTo, 'Evening');
  });

  testWidgets('renaming another viewer leaves the account name alone', (
    tester,
  ) async {
    final store = _RecordingProfileStore();
    final auth = _RecordingAuthCubit();
    GetIt.instance.registerSingleton<AuthCubit>(auth);
    addTearDown(() async {
      await GetIt.instance.unregister<AuthCubit>();
      await auth.close();
    });
    await tester.pumpWidget(
      _profileStoreEditorHost(
        store,
        editingProfile: const ViewerProfile(id: 'guest', name: 'Guest'),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Family');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(auth.renamedTo, isNull);
    expect(store.renamedTo, 'Family');
  });

  testWidgets('failed account rename leaves Home name unchanged', (
    tester,
  ) async {
    final store = _RecordingProfileStore();
    final auth = _RecordingAuthCubit()..succeeds = false;
    GetIt.instance.registerSingleton<AuthCubit>(auth);
    addTearDown(() async {
      await GetIt.instance.unregister<AuthCubit>();
      await auth.close();
    });
    await tester.pumpWidget(_profileStoreEditorHost(store));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Evening');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(auth.renamedTo, 'Evening');
    expect(store.renamedTo, isNull);
    expect(find.text('Could not update account name'), findsOneWidget);
  });

  testWidgets('failed Home rename restores the account name', (tester) async {
    final store = _RecordingProfileStore()..renameSucceeds = false;
    final auth = _RecordingAuthCubit();
    GetIt.instance.registerSingleton<AuthCubit>(auth);
    addTearDown(() async {
      await GetIt.instance.unregister<AuthCubit>();
      await auth.close();
    });
    await tester.pumpWidget(_profileStoreEditorHost(store));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Evening');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(auth.renameCalls, ['Evening', 'Home']);
    expect(store.renameCalls, ['Evening', 'Home']);
    expect(find.text('Could not update profile name'), findsOneWidget);
  });
}

class _RecordingAuthCubit extends Cubit<AuthState> implements AuthCubit {
  _RecordingAuthCubit()
    : super(
        const AuthState(
          status: AuthStatus.authenticated,
          user: AuthUser(id: 'user', name: 'Home', email: 'user@example.com'),
        ),
      );

  String? renamedTo;
  final renameCalls = <String>[];
  bool succeeds = true;

  @override
  Future<bool> updateName(String name) async {
    renamedTo = name;
    renameCalls.add(name);
    return succeeds;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingProfileStore extends ViewerProfileStore {
  List<ViewerProfile> visibleProfiles = [];
  bool synced = false;
  String? renamedTo;
  final renameCalls = <String>[];
  bool renameSucceeds = true;
  int? updatedAvatar;
  bool? updatedIsKids;
  String? updatedPhotoUrl;
  bool? clearedPhotoUrl;

  @override
  List<ViewerProfile> get profiles => visibleProfiles;

  @override
  Future<bool> rename(String profileId, String name) async {
    renamedTo = name;
    renameCalls.add(name);
    return renameSucceeds;
  }

  @override
  Future<bool> update(
    String profileId, {
    int? avatar,
    bool? isKids,
    String? photoUrl,
    bool clearPhotoUrl = false,
  }) async {
    updatedAvatar = avatar;
    updatedIsKids = isKids;
    updatedPhotoUrl = photoUrl;
    clearedPhotoUrl = clearPhotoUrl;
    return synced;
  }
}
