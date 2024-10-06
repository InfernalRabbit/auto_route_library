import 'package:flutter/material.dart';

import '../../../auto_route.dart';

/// A Wrapper for [Navigator] that handles stack-routing
class AutoRouter extends StatefulWidget {
  /// A builder function that returns a list of observes
  ///
  /// Why isn't this a list of navigatorObservers?
  /// The reason for that is a [NavigatorObserver] instance can only
  /// be used by a single [Navigator], so unless you're using a one
  /// single router or you don't want your nested routers to inherit
  /// observers make sure navigatorObservers builder always returns
  /// fresh observer instances.
  final NavigatorObserversBuilder navigatorObservers;

  /// This builder maybe used to build content with context
  /// that has [AutoRouterState.controller]
  final Widget Function(BuildContext context, Widget content)? builder;

  /// Passed to [Navigator.restorationScopeId]
  final String? navRestorationScopeId;

  /// Whether this router should inherit it's ancestor's observers
  final bool inheritNavigatorObservers;

  /// The state key passed to [Navigator]
  final GlobalKey<NavigatorState>? navigatorKey;

  /// A builder for the placeholder page that is shown
  /// before the first route can be rendered. Defaults to
  /// an empty page with [Theme.scaffoldBackgroundColor].
  final WidgetBuilder? placeholder;

  /// Default constructor
  const AutoRouter({
    super.key,
    this.navigatorObservers =
        AutoRouterDelegate.defaultNavigatorObserversBuilder,
    this.builder,
    this.navRestorationScopeId,
    this.navigatorKey,
    this.inheritNavigatorObservers = true,
    this.placeholder,
  });

  /// Builds a [_DeclarativeAutoRouter] which uses
  /// a declarative list of routes to update navigator stack
  factory AutoRouter.declarative({
    Key? key,
    NavigatorObserversBuilder navigatorObservers =
        AutoRouterDelegate.defaultNavigatorObserversBuilder,
    required RoutesBuilder routes,
    RoutePopCallBack? onPopRoute,
    String? navRestorationScopeId,
    bool inheritNavigatorObservers = true,
    GlobalKey<NavigatorState>? navigatorKey,
    OnNestedNavigateCallBack? onNavigate,
    WidgetBuilder? placeholder,
  }) =>
      _DeclarativeAutoRouter(
        key: key,
        onPopRoute: onPopRoute,
        navigatorKey: navigatorKey,
        navRestorationScopeId: navRestorationScopeId,
        navigatorObservers: navigatorObservers,
        inheritNavigatorObservers: inheritNavigatorObservers,
        onNavigate: onNavigate,
        placeholder: placeholder,
        routes: routes,
      );

  /// Builds a [_ParalelAutoRouter] which uses
  /// a list of routes to show in current navigator
  factory AutoRouter.parallel({
    Key? key,
    NavigatorObserversBuilder navigatorObservers =
        AutoRouterDelegate.defaultNavigatorObserversBuilder,
    Widget Function(BuildContext context, Widget content)? builder,
    String? navRestorationScopeId,
    GlobalKey<NavigatorState>? navigatorKey,
    bool inheritNavigatorObservers = true,
    WidgetBuilder? placeholder,
    required List<String>? routes,
  }) =>
      _ParalelAutoRouter(
        key: key,
        navigatorObservers: navigatorObservers,
        builder: builder,
        navigatorKey: navigatorKey,
        navRestorationScopeId: navRestorationScopeId,
        inheritNavigatorObservers: inheritNavigatorObservers,
        placeholder: placeholder,
        routes: routes,
      );

  @override
  State<AutoRouter> createState() => AutoRouterState();

  /// Looks up and returns the scoped [StackRouter]
  ///
  /// if watch is true dependent widget will watch changes
  /// of this scope otherwise it would just read it
  ///
  /// throws an error if it does not find it
  static StackRouter of(BuildContext context, {bool watch = false}) {
    var scope = StackRouterScope.of(context, watch: watch);
    assert(() {
      if (scope == null) {
        throw FlutterError(
            'AutoRouter operation requested with a context that does not include an AutoRouter.\n'
            'The context used to retrieve the Router must be that of a widget that '
            'is a descendant of an AutoRouter widget.');
      }
      return true;
    }());
    return scope!.controller;
  }

  /// Helper to access [RoutingController.innerRouterOf]
  static StackRouter? innerRouterOf(BuildContext context, String routeName) {
    return of(context).innerRouterOf<StackRouter>(routeName);
  }
}

/// State implementation of [AutoRouter]
class AutoRouterState extends State<AutoRouter> {
  StackRouter? _controller;

  /// The StackRouter controlling this router widget
  StackRouter? get controller => _controller;
  late List<NavigatorObserver> _navigatorObservers;
  late NavigatorObserversBuilder _inheritableObserversBuilder;
  late RoutingController _parentController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null) {
      final parentRouteData = RouteData.of(context);
      final parentScope = RouterScope.of(context, watch: true);
      _inheritableObserversBuilder = () {
        var observers = widget.navigatorObservers();
        if (!widget.inheritNavigatorObservers) {
          return observers;
        }
        var inheritedObservers = parentScope.inheritableObserversBuilder();
        return inheritedObservers + observers;
      };
      _navigatorObservers = _inheritableObserversBuilder();
      _parentController = parentScope.controller;
      _controller = NestedStackRouter(
        parent: _parentController,
        key: parentRouteData.key,
        routeData: parentRouteData,
        navigatorKey: widget.navigatorKey,
        routeCollection: _parentController.routeCollection.subCollectionOf(
          parentRouteData.name,
        ),
      );
      _parentController.attachChildController(_controller!);
      _controller!.addListener(_rebuildListener);
    }
  }

  void _rebuildListener() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    assert(_controller != null);
    var navigator = AutoRouteNavigator(
      router: _controller!,
      key: GlobalObjectKey(_controller.hashCode),
      navRestorationScopeId: widget.navRestorationScopeId,
      navigatorObservers: _navigatorObservers,
      placeholder: widget.placeholder,
    );
    final stateHash = _controller!.stateHash;
    return RouterScope(
      controller: _controller!,
      inheritableObserversBuilder: _inheritableObserversBuilder,
      navigatorObservers: _navigatorObservers,
      stateHash: stateHash,
      child: StackRouterScope(
        controller: _controller!,
        stateHash: stateHash,
        child: widget.builder == null
            ? navigator
            : Builder(
                builder: (ctx) => widget.builder!(ctx, navigator),
              ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
    if (_controller != null) {
      _controller!.removeListener(_rebuildListener);
      _controller!.dispose();
      _parentController.removeChildController(_controller!);
      _controller = null;
    }
  }
}

class _DeclarativeAutoRouter extends AutoRouter {
  final RoutesBuilder routes;
  final RoutePopCallBack? onPopRoute;
  final OnNestedNavigateCallBack? onNavigate;

  const _DeclarativeAutoRouter({
    super.key,
    required this.routes,
    super.navigatorObservers =
        AutoRouterDelegate.defaultNavigatorObserversBuilder,
    this.onPopRoute,
    super.navigatorKey,
    super.navRestorationScopeId,
    super.inheritNavigatorObservers = true,
    this.onNavigate,
    super.placeholder,
  }) : super();

  @override
  _DeclarativeAutoRouterState createState() => _DeclarativeAutoRouterState();
}

class _DeclarativeAutoRouterState extends State<_DeclarativeAutoRouter> {
  StackRouter? _controller;
  late HeroController _heroController;

  StackRouter? get controller => _controller;
  late List<NavigatorObserver> _navigatorObservers;
  late NavigatorObserversBuilder _inheritableObserversBuilder;
  late RoutingController _parentController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final parentData = RouteData.of(context);
    if (_controller == null) {
      _heroController = HeroController();
      final parentScope = RouterScope.of(context);
      _inheritableObserversBuilder = () {
        var observers = widget.navigatorObservers();
        if (!widget.inheritNavigatorObservers) {
          return observers;
        }
        var inheritedObservers = parentScope.inheritableObserversBuilder();
        return inheritedObservers + observers;
      };
      _navigatorObservers = _inheritableObserversBuilder();
      _parentController = parentScope.controller;
      _controller = NestedStackRouter(
        parent: _parentController,
        key: parentData.key,
        routeData: parentData,
        managedByWidget: true,
        onNavigate: widget.onNavigate,
        navigatorKey: widget.navigatorKey,
        routeCollection: _parentController.routeCollection.subCollectionOf(
          parentData.name,
        ),
      );
      _parentController.attachChildController(_controller!);
    }
  }

  @override
  void dispose() {
    super.dispose();
    if (_controller != null) {
      _controller!.dispose();
      _parentController.removeChildController(_controller!);
      _controller = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    assert(_controller != null);
    final stateHash = controller!.stateHash;
    return RouterScope(
      controller: _controller!,
      inheritableObserversBuilder: _inheritableObserversBuilder,
      navigatorObservers: _navigatorObservers,
      stateHash: stateHash,
      child: HeroControllerScope(
        controller: _heroController,
        child: AutoRouteNavigator(
          router: _controller!,
          key: GlobalObjectKey(_controller.hashCode),
          declarativeRoutesBuilder: widget.routes,
          navRestorationScopeId: widget.navRestorationScopeId,
          navigatorObservers: _navigatorObservers,
          didPop: widget.onPopRoute,
          placeholder: widget.placeholder,
        ),
      ),
    );
  }
}

/// A Wrapper for [Navigator] that handles stack-routing
class _ParalelAutoRouter extends AutoRouter {
  /// A List of route names that rendered separately
  final List<String>? routes;

  /// Default constructor
  const _ParalelAutoRouter({
    super.key,
    super.navigatorObservers =
        AutoRouterDelegate.defaultNavigatorObserversBuilder,
    super.builder,
    super.navRestorationScopeId,
    super.navigatorKey,
    super.inheritNavigatorObservers = true,
    super.placeholder,
    this.routes,
  }) : super();

  @override
  State<_ParalelAutoRouter> createState() => ParalelAutoRouterState();
}

/// State implementation of [_ParalelAutoRouter]
class ParalelAutoRouterState extends State<_ParalelAutoRouter> {
  StackRouter? _controller;

  /// The StackRouter controlling this router widget
  StackRouter? get controller => _controller;
  late List<NavigatorObserver> _navigatorObservers;
  late NavigatorObserversBuilder _inheritableObserversBuilder;
  late RoutingController _parentController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null) {
      final parentRouteData = RouteData.of(context);
      final parentScope = RouterScope.of(context, watch: true);
      _inheritableObserversBuilder = () {
        var observers = widget.navigatorObservers();
        if (!widget.inheritNavigatorObservers) {
          return observers;
        }
        var inheritedObservers = parentScope.inheritableObserversBuilder();
        return inheritedObservers + observers;
      };
      _navigatorObservers = _inheritableObserversBuilder();
      _parentController = parentScope.controller;
      final subCollection = _parentController.routeCollection.subCollectionOf(
        parentRouteData.name,
      );
      _controller = NestedStackRouter(
        parent: _parentController,
        key: parentRouteData.key,
        routeData: parentRouteData,
        navigatorKey: widget.navigatorKey,
        routeCollection: widget.routes != null
            ? RouteCollection.fromList(subCollection.routes
                .where((e) => widget.routes?.contains(e.name) ?? true)
                .toList())
            : subCollection,
        pageBuilder: _parentController.pageBuilder,
      );

      _parentController.attachChildController(_controller!);
      _controller!.addListener(_rebuildListener);
    }
  }

  void _rebuildListener() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    assert(_controller != null);
    var navigator = AutoRouteNavigator(
      router: _controller!,
      navRestorationScopeId: widget.navRestorationScopeId,
      navigatorObservers: _navigatorObservers,
      placeholder: widget.placeholder,
    );
    final stateHash = controller!.stateHash;
    return RouterScope(
      controller: _controller!,
      inheritableObserversBuilder: _inheritableObserversBuilder,
      navigatorObservers: _navigatorObservers,
      stateHash: stateHash,
      child: StackRouterScope(
        controller: _controller!,
        stateHash: stateHash,
        child: widget.builder == null
            ? navigator
            : Builder(
                builder: (ctx) => widget.builder!(ctx, navigator),
              ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
    if (_controller != null) {
      _controller!.removeListener(_rebuildListener);
      _controller!.dispose();
      _parentController.removeChildController(_controller!);
      _controller = null;
    }
  }
}
