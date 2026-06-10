// Static regression guard for the "listen outside build" crash class.
//
// `context.colors` / `context.isDarkTheme` / `context.isLightTheme`
// (lib/theme/theme_extension.dart) are LISTENING `Provider.of` reads. Called
// from an event handler (onTap/onPressed/onChanged…, a `.then` callback, a
// Timer / post-frame callback), Flutter asserts "listen outside build" in
// DEBUG builds only — and surrounding code often swallows the error, so the
// action silently does nothing while release builds look fine. This class has
// shipped three times (v0.5.1 right-click Delete; five dead menus in v0.6
// batch 2; the sampler Root Note dropdown, bug-hunt #23).
//
// This test parses the AST of every file under lib/ and fails if a listening
// read appears inside a handler-position closure that CAPTURES its
// BuildContext from an enclosing scope. Closures handed their own fresh
// BuildContext (builder:, itemBuilder:, an overlay/dialog builder) run during
// build and are exempt.
//
// Fix at a call site: use `context.themeProvider.colors` (listen: false) or
// capture the colors in build() / inside the builder closure.
// Full rule: .claude/rules/flutter-ui.md.
//
// Limitations (a clean pass is NOT proof the class is absent):
// - Exactly ONE level of method indirection is tracked. `onTap: _methodA`
//   where `_methodA` reads context.colors is caught; `onTap: _methodA` where
//   `_methodA` calls `_methodB` which reads context.colors is NOT — the
//   _pendingByMethod/_handlerInvokedMethods resolution does not chase
//   transitive calls.
// - Method matching is by NAME within a file, not by class: if two classes in
//   the same file declare a method with the same name and only one is wired
//   to a handler, a listening read in the other is a false positive (and the
//   _allowlist is the escape hatch).

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The listening extension getters on BuildContext (theme_extension.dart).
const _listeningGetters = {'colors', 'isDarkTheme', 'isLightTheme'};

/// Method names whose closure arguments run OUTSIDE the build phase.
const _deferredCallbackMethods = {
  'then',
  'catchError',
  'whenComplete',
  'addPostFrameCallback',
};

/// Known-safe violations. Last resort — prefer fixing the call site or
/// refining the heuristic. Keyed by posix-style path relative to lib/, value
/// is the reason it is safe.
const Map<String, String> _allowlist = {};

void main() {
  test('no listening Provider reads inside event handlers (lib/**)', () {
    final libDir = _findLibDir();
    final violations = <String>[];

    final dartFiles =
        libDir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in dartFiles) {
      final relative = p
          .relative(file.path, from: libDir.path)
          .replaceAll(r'\', '/');
      if (relative == p.posix.join('theme', 'theme_extension.dart')) {
        continue; // the getters' own definitions
      }
      if (_allowlist.containsKey(relative)) continue;

      final result = parseString(
        content: file.readAsStringSync(),
        path: file.path,
        throwIfDiagnostics: false,
      );
      final visitor = _ListenOutsideBuildVisitor();
      result.unit.accept(visitor);

      for (final hit in visitor.allHits()) {
        final loc = result.lineInfo.getLocation(hit.offset);
        violations.add('lib/$relative:${loc.lineNumber}: ${hit.message}');
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Listening Provider reads inside event handlers assert '
          '"listen outside build" in DEBUG builds and usually die silently '
          '(see .claude/rules/flutter-ui.md). Use context.themeProvider.colors '
          '(listen: false) or capture colors in build().\n\n'
          'Violations:\n${violations.join('\n')}\n',
    );
  });
}

Directory _findLibDir() {
  var dir = Directory.current;
  for (var i = 0; i < 5; i++) {
    final lib = Directory(p.join(dir.path, 'lib'));
    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    if (lib.existsSync() && pubspec.existsSync()) return lib;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('Could not locate lib/ walking up from ${Directory.current.path}');
}

class _Hit {
  _Hit(this.offset, this.message);
  final int offset;
  final String message;
}

class _ListenOutsideBuildVisitor extends RecursiveAstVisitor<void> {
  final hits = <_Hit>[];

  /// Listening reads whose walk-up ended at a named method/function — only a
  /// violation if that method turns out to be invoked from a handler.
  final _pendingByMethod = <String, List<_Hit>>{};

  /// Methods/local functions referenced as handler tearoffs
  /// (`onTap: _showMenu`, `.then(_handle)`) or called from inside a
  /// handler-position closure (`onTap: () => _showMenu()`). A listening read
  /// inside one of these runs at event time, not during build.
  final _handlerInvokedMethods = <String>{};

  /// Resolved hits: direct ones plus pending reads inside handler-invoked
  /// methods. Call after the visit completes.
  Iterable<_Hit> allHits() sync* {
    yield* hits;
    for (final entry in _pendingByMethod.entries) {
      if (_handlerInvokedMethods.contains(entry.key)) {
        yield* entry.value;
      }
    }
  }

  // -- handler tearoffs: `onTap: _showMenu` ----------------------------------

  @override
  void visitNamedArgument(NamedArgument node) {
    if (RegExp('^on[A-Z]').hasMatch(node.name.lexeme)) {
      final value = node.argumentExpression;
      if (value is SimpleIdentifier) {
        _handlerInvokedMethods.add(value.name);
      }
    }
    super.visitNamedArgument(node);
  }

  // -- listening extension getters: `context.colors` etc. --------------------

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    // `context.colors` parses as PrefixedIdentifier.
    if (_listeningGetters.contains(node.identifier.name) &&
        _isContextLike(node.prefix.name)) {
      _check(node, node.prefix.name, 'context.${node.identifier.name}');
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    // `this.context.colors` / chained targets parse as PropertyAccess.
    final target = node.target;
    if (_listeningGetters.contains(node.propertyName.name)) {
      String? ctxName;
      if (target is SimpleIdentifier && _isContextLike(target.name)) {
        ctxName = target.name;
      } else if (target is PropertyAccess &&
          _isContextLike(target.propertyName.name)) {
        ctxName = target.propertyName.name;
      }
      if (ctxName != null) {
        _check(node, ctxName, 'context.${node.propertyName.name}');
      }
    }
    super.visitPropertyAccess(node);
  }

  // -- raw listening Provider.of ---------------------------------------------

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target;
    if (node.methodName.name == 'of' &&
        target is SimpleIdentifier &&
        target.name == 'Provider' &&
        _isListeningProviderOf(node)) {
      final args = node.argumentList.arguments;
      final first = args.isNotEmpty ? args.first : null;
      final ctxName = first is SimpleIdentifier ? first.name : 'context';
      _check(node, ctxName, 'listening Provider.of');
    }

    // provider's `context.watch<T>()` / `context.select<T, R>(...)` are also
    // listening reads (unused today, guarded for the future).
    if ((node.methodName.name == 'watch' || node.methodName.name == 'select') &&
        target is SimpleIdentifier &&
        _isContextLike(target.name)) {
      _check(node, target.name, 'context.${node.methodName.name}');
    }

    // Tearoffs handed to deferred callbacks: `.then(_handle)`,
    // `addPostFrameCallback(_onFrame)`, `Future.delayed(d, _cb)`.
    if (_isDeferredCallbackInvocation(node)) {
      for (final arg in node.argumentList.arguments) {
        if (arg is SimpleIdentifier) {
          _handlerInvokedMethods.add(arg.name);
        }
      }
    }

    // `onTap: () => _showMenu()` — an untargeted call inside a
    // handler-position closure makes the callee run at event time.
    if ((target == null || target is ThisExpression) &&
        _isInsideHandlerClosure(node)) {
      _handlerInvokedMethods.add(node.methodName.name);
    }

    super.visitMethodInvocation(node);
  }

  bool _isDeferredCallbackInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if (_deferredCallbackMethods.contains(name) || name == 'Timer') {
      return true;
    }
    final target = node.target;
    if (target is SimpleIdentifier) {
      if (target.name == 'Timer' && name == 'periodic') return true;
      if (target.name == 'Future' && name == 'delayed') return true;
    }
    return false;
  }

  /// Whether [node] executes at event time: its nearest classified enclosing
  /// closure is in handler position (builder closures run during build).
  bool _isInsideHandlerClosure(AstNode node) {
    AstNode? current = node.parent;
    while (current != null) {
      if (current is FunctionExpression) {
        switch (_closureRole(current)) {
          case _Role.handler:
            return true;
          case _Role.builder:
            return false;
          case _Role.other:
            break;
        }
      }
      if (current is MethodDeclaration ||
          current is FunctionDeclaration ||
          current is ConstructorDeclaration) {
        return false;
      }
      current = current.parent;
    }
    return false;
  }

  /// Listening unless an explicit `listen: false` literal is passed.
  bool _isListeningProviderOf(MethodInvocation node) {
    for (final arg in node.argumentList.arguments) {
      if (arg is NamedArgument && arg.name.lexeme == 'listen') {
        final value = arg.argumentExpression;
        if (value is BooleanLiteral && !value.value) return false;
        // `listen: true` or a non-literal — treat as listening.
        return true;
      }
    }
    return true; // default is listen: true
  }

  // -- enclosing-scope classification ----------------------------------------

  /// Flags [node] if it sits inside a handler-position closure that captures
  /// [ctxName] from an enclosing scope (rather than declaring it).
  void _check(AstNode node, String ctxName, String what) {
    AstNode? current = node.parent;
    while (current != null) {
      if (current is FunctionExpression) {
        final params = current.parameters?.parameters ?? <FormalParameter>[];
        if (params.any((fp) => fp.name?.lexeme == ctxName)) {
          // The closure is handed its own BuildContext — a builder running
          // during build. Safe.
          return;
        }
        switch (_closureRole(current)) {
          case _Role.handler:
            hits.add(
              _Hit(
                node.offset,
                '$what read inside ${_describeHandler(current)} — listening '
                'read of captured `$ctxName` outside build',
              ),
            );
            return;
          case _Role.builder:
            // builder/itemBuilder/etc. run during the build phase.
            return;
          case _Role.other:
            break; // plain closure (forEach, local fn) — keep walking up.
        }
      }
      if (current is MethodDeclaration ||
          current is FunctionDeclaration ||
          current is ConstructorDeclaration) {
        // Reached a named declaration without passing a handler closure.
        // Build helpers are fine — but if this method is invoked FROM a
        // handler (`onTap: _showMenu` tearoff, or `onTap: () => _showMenu()`),
        // the read runs at event time (the sampler Root Note bug, #23).
        // Record as pending; resolved against handler-invoked methods after
        // the full file visit.
        final name = switch (current) {
          MethodDeclaration(:final name) => name.lexeme,
          FunctionDeclaration(:final name) => name.lexeme,
          _ => null,
        };
        if (name != null) {
          _pendingByMethod
              .putIfAbsent(name, () => [])
              .add(
                _Hit(
                  node.offset,
                  '$what read in `$name()`, which is invoked from an event '
                  'handler — listening read outside build',
                ),
              );
        }
        return;
      }
      current = current.parent;
    }
  }

  _Role _closureRole(FunctionExpression fe) {
    final parent = fe.parent;
    if (parent is NamedArgument) {
      final name = parent.name.lexeme;
      if (name.endsWith('uilder')) return _Role.builder; // *builder, *Builder
      if (RegExp('^on[A-Z]').hasMatch(name)) return _Role.handler;
      return _Role.other;
    }
    if (parent is ArgumentList) {
      final call = parent.parent;
      if (call is MethodInvocation) {
        final name = call.methodName.name;
        if (_deferredCallbackMethods.contains(name)) return _Role.handler;
        // `Timer(d, cb)` parses as a MethodInvocation named Timer;
        // `Timer.periodic` / `Future.delayed` have a prefix target.
        if (name == 'Timer') return _Role.handler;
        final target = call.target;
        if (target is SimpleIdentifier) {
          if (target.name == 'Timer' && name == 'periodic') {
            return _Role.handler;
          }
          if (target.name == 'Future' && name == 'delayed') {
            return _Role.handler;
          }
        }
      }
      if (call is InstanceCreationExpression) {
        final typeName = call.constructorName.type.name.lexeme;
        if (typeName == 'Timer') return _Role.handler;
      }
    }
    return _Role.other;
  }

  String _describeHandler(FunctionExpression fe) {
    final parent = fe.parent;
    if (parent is NamedArgument) {
      return '`${parent.name.lexeme}:` handler';
    }
    if (parent is ArgumentList) {
      final call = parent.parent;
      if (call is MethodInvocation) {
        final target = call.target;
        final prefix = target is SimpleIdentifier
            ? '${target.name}.'
            : (target == null ? '' : '.');
        return '`$prefix${call.methodName.name}()` callback';
      }
      if (call is InstanceCreationExpression) {
        return '`${call.constructorName.type.name.lexeme}()` callback';
      }
    }
    return 'deferred callback';
  }

  bool _isContextLike(String name) {
    final lower = name.toLowerCase();
    return lower == 'context' || lower == 'ctx' || lower.endsWith('context');
  }
}

enum _Role { handler, builder, other }
