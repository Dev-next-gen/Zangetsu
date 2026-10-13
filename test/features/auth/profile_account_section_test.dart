import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/app_mode.dart';
import 'package:watch_app/core/profiles/viewer_profile.dart';
import 'package:watch_app/core/supabase/auth_user.dart';
import 'package:watch_app/features/auth/auth_cubit.dart';
import 'package:watch_app/features/auth/auth_screens.dart';

void main() {
  late Directory directory;
  late ViewerProfileStore profiles;
  late _TestAuthCubit auth;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('profile_account');
    Hive.init(directory.path);
    await ViewerProfileStore.init();
    profiles = ViewerProfileStore();
    await profiles.loadForUser(displayName: 'Account');
    await GetIt.instance.reset();
    GetIt.instance
      ..registerSingleton<AppMode>(const AppMode(isTv: false))
      ..registerSingleton<ViewerProfileStore>(profiles);
    auth = _TestAuthCubit();
  });

  tearDown(() async {
    await auth.close();
    await GetIt.instance.reset();
    await Hive.deleteFromDisk();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  testWidgets('account avatar follows the default profile photo', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Offstage(
          offstage: true,
          child: BlocProvider<AuthCubit>.value(
            value: auth,
            child: const Scaffold(body: ProfileAccountSection()),
          ),
        ),
      ),
    );

    expect(_accountAvatarUrl(tester), 'https://example.com/legacy-account.jpg');

    await tester.runAsync(
      () => profiles.update(
        kDefaultProfileId,
        photoUrl: 'https://example.com/main-profile.jpg',
      ),
    );
    await tester.pump();

    expect(_accountAvatarUrl(tester), 'https://example.com/main-profile.jpg');

    final guest = await tester.runAsync(() => profiles.create('Guest'));
    await tester.runAsync(
      () =>
          profiles.update(guest!.id, photoUrl: 'https://example.com/guest.jpg'),
    );
    await tester.pump();
    expect(_accountAvatarUrl(tester), 'https://example.com/main-profile.jpg');

    await tester.runAsync(
      () => profiles.update(kDefaultProfileId, clearPhotoUrl: true),
    );
    await tester.pump();
    expect(_accountAvatarUrl(tester), 'https://example.com/legacy-account.jpg');
  });

  testWidgets('account avatar picker offers animated GIFs', (tester) async {
    final previousPicker = FilePickerPlatform.instance;
    final picker = _FakeFilePickerPlatform();
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = previousPicker);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<AuthCubit>.value(
            value: auth,
            child: const ProfileAccountSection(),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(CircleAvatar).first);
    await tester.pumpAndSettle();

    expect(find.text('Photo from gallery'), findsOneWidget);
    expect(find.text('Animated GIF file'), findsOneWidget);

    await tester.tap(find.text('Animated GIF file'));
    await tester.pumpAndSettle();

    expect(picker.requestedType, FileType.custom);
    expect(picker.requestedExtensions, ['gif']);
  });

  testWidgets('renaming the account also renames the default profile', (
    tester,
  ) async {
    final accountProfiles = await _registerFastProfiles([
      const ViewerProfile(id: kDefaultProfileId, name: 'Account'),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<AuthCubit>.value(
            value: auth,
            child: const ProfileAccountSection(),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Tamanna');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(auth.updatedName, 'Tamanna');
    expect(
      accountProfiles.profiles.firstWhere((profile) => profile.isDefault).name,
      'Tamanna',
    );
  });

  testWidgets('saving the account name repairs a stale default profile', (
    tester,
  ) async {
    final accountProfiles = await _registerFastProfiles([
      const ViewerProfile(id: kDefaultProfileId, name: 'Taman'),
    ]);
    await auth.updateName('Tamanna');
    final accountUpdatesBeforeSave = auth.nameUpdateCount;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<AuthCubit>.value(
            value: auth,
            child: const ProfileAccountSection(),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Tamanna'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      accountProfiles.profiles.firstWhere((profile) => profile.isDefault).name,
      'Tamanna',
    );
    expect(auth.nameUpdateCount, accountUpdatesBeforeSave);
  });
}

Future<_FastViewerProfileStore> _registerFastProfiles(
  List<ViewerProfile> profiles,
) async {
  await GetIt.instance.unregister<ViewerProfileStore>();
  final store = _FastViewerProfileStore(profiles);
  GetIt.instance.registerSingleton<ViewerProfileStore>(store);
  return store;
}

String? _accountAvatarUrl(WidgetTester tester) =>
    (tester
                .widget<CircleAvatar>(
                  find.byType(CircleAvatar, skipOffstage: false),
                )
                .backgroundImage
            as CachedNetworkImageProvider?)
        ?.url;

class _TestAuthCubit extends Cubit<AuthState> implements AuthCubit {
  String? updatedName;
  int nameUpdateCount = 0;

  _TestAuthCubit()
    : super(
        const AuthState(
          status: AuthStatus.authenticated,
          user: AuthUser(id: 'user-1', name: 'Account', email: 'a@example.com'),
          avatarUrl: 'https://example.com/legacy-account.jpg',
        ),
      );

  @override
  Future<bool> updateName(String name) async {
    nameUpdateCount++;
    updatedName = name;
    final current = state.user!;
    emit(
      state.copyWith(
        user: () => AuthUser(
          id: current.id,
          name: name,
          email: current.email,
          avatarPath: current.avatarPath,
        ),
      ),
    );
    return true;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FastViewerProfileStore extends ViewerProfileStore {
  _FastViewerProfileStore(this._profiles);

  List<ViewerProfile> _profiles;

  @override
  List<ViewerProfile> get profiles => List.unmodifiable(_profiles);

  @override
  Future<bool> rename(String profileId, String name) async {
    if (!_profiles.any((profile) => profile.id == profileId)) return false;
    _profiles = [
      for (final profile in _profiles)
        if (profile.id == profileId) profile.copyWith(name: name) else profile,
    ];
    revision.value++;
    return true;
  }
}

class _FakeFilePickerPlatform extends FilePickerPlatform {
  FileType? requestedType;
  List<String>? requestedExtensions;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus status)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    requestedType = type;
    requestedExtensions = allowedExtensions;
    return null;
  }
}
