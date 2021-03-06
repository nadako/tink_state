package tink.state;

private typedef BindingOptions<T> = Deprecated<{
  ?direct:Bool,
  ?comparator:T->T->Bool,
}>;

@:forward
abstract Deprecated<T>(T) {
  @:deprecated
  @:from static function of<X>(v:X):Deprecated<X>
    return cast v;
}

#if tink_state.debug
  @:forward(toString)
#end
@:using(tink.state.Observable.ObservableTools)
abstract Observable<T>(ObservableObject<T>) from ObservableObject<T> to ObservableObject<T> {
  public var value(get, never):T;
    @:to function get_value()
      return AutoObservable.track(this);

  static public inline function untracked<T>(fn:Void->T)
    return AutoObservable.untracked(fn);

  public function bind(
    #if tink_state.legacy_binding_options ?options:BindingOptions<T>, #end
    cb:Callback<T>, ?comparator:Comparator<T>, ?scheduler:Scheduler
  ):CallbackLink {
    #if tink_state.legacy_binding_options
      if (options != null) {
        comparator = options.comparator;
        if (options.direct) scheduler = Scheduler.direct;
      }
    #end
    if (scheduler == null)
      scheduler = Observable.scheduler;
    return new Binding(this, cb, scheduler, comparator).cancel;
  }

  public inline function new(get:Void->T, changed:Signal<Noise>, ?toString #if tink_state.debug , ?pos:haxe.PosInfos #end)
    this = new SignalObservable(get, changed, toString #if tink_state.debug , pos #end);

  public function combine<A, R>(that:Observable<A>, f:T->A->R):Observable<R>
    return Observable.auto(() -> f(value, that.value));

  public function nextTime(?options:{ ?butNotNow: Bool, ?hires:Bool }, check:T->Bool):Future<T>
    return getNext(options, function (v) return if (check(v)) Some(v) else None);

  public function getNext<R>(?options:{ ?butNotNow: Bool, ?hires:Bool }, select:T->Option<R>):Future<R> {
    var ret = Future.trigger(),
        waiting = options != null && options.butNotNow;

    var link = bind(function (value) {
      var out = select(value);
      if (waiting)
        waiting = out != None;
      else switch out {
        case Some(value): ret.trigger(value);
        case None:
      }
    }, if (options != null && options.hires) Scheduler.direct else null);

    ret.handle(link.cancel);

    return ret;
  }

  public function join(that:Observable<T>) {
    var lastA = null;
    return combine(that, function (a, b) {
      var ret =
        if (lastA == a) b;
        else a;

      lastA = a;
      return ret;
    });
  }

  public function map<R>(f:Transform<T, R>):Observable<R>
    return Observable.auto(() -> f.apply(value));//TODO: benchmark TransformObservable and if it's noticably faster, use it
    // return new TransformObservable(this, f);

  public function combineAsync<A, R>(that:Observable<A>, f:T->A->Promise<R>):Observable<Promised<R>>
     return Observable.auto(() -> f(value, that.value));

  public function mapAsync<R>(f:Transform<T, Promise<R>>):Observable<Promised<R>>
    return Observable.auto(() -> f.apply(this.getValue()));

  @:deprecated('use auto instead')
  public function switchSync<R>(cases:Array<{ when: T->Bool, then: Lazy<Observable<R>> } > , dfault:Lazy<Observable<R>>):Observable<R>
    return Observable.auto(() -> {
      var v = value;
      for (c in cases)
        if (c.when(v)) {
          dfault = c.then;
          break;
        }
      return dfault.get().value;
    });

  static var scheduler:Scheduler =
    #if macro
      Scheduler.direct;
    #else
      Scheduler.batched(Scheduler.batcher());
    #end

  static public inline function schedule(f:Void->Void)
    scheduler.run(f);

  static public var isUpdating(default, null):Bool = false;

  @:extern static inline function performUpdate<T>(fn:Void->T) {
    var wasUpdating = isUpdating;
    isUpdating = true;
    return Error.tryFinally(fn, () -> isUpdating = wasUpdating);
  }

  static public function updatePending(maxSeconds:Float = .01)
    return !isUpdating && scheduler.progress(maxSeconds);

  static public function updateAll()
    updatePending(Math.POSITIVE_INFINITY);

  static public inline function lift<T>(o:Observable<T>) return o;

  static public function ofPromise<T>(p:Promise<T>):Observable<Promised<T>>
    return Observable.auto(() -> p);

  @:deprecated
  static public function create<T>(f, ?comparator, ?toString #if tink_state.debug , ?pos:haxe.PosInfos #end):Observable<T>
    return new SimpleObservable(f, comparator, toString #if tink_state.debug , pos #end);

  @:noUsing static public inline function auto<T>(f, ?comparator, ?toString #if tink_state.debug , ?pos:haxe.PosInfos #end):Observable<T>
    return new AutoObservable<T>(f, comparator, toString #if tink_state.debug , pos #end);

  @:noUsing static public inline function const<T>(value:T, ?toString #if tink_state.debug , ?pos:haxe.PosInfos #end):Observable<T>
    return new ConstObservable(value, toString #if tink_state.debug , pos #end);

  @:op(a == b)
  static function eq<T>(a:Observable<T>, b:Observable<T>):Bool
    return switch [a, b] {
      case [null, null]: true;
      case [null, _] | [_, null]: false;
      default: a.value == b.value;
    }

  @:op(a != b)
  static inline function neq<T>(a:Observable<T>, b:Observable<T>):Bool
    return !eq(a, b);

  #if tink_state.test_subscriptions
    static function subscriptionCount()
      return @:privateAccess AutoObservable.subscriptionCount;
  #end

  #if tink_state.debug
    public function dependencyTree():DependencyTree
      return new DependencyTree(cast this);
  #end

}

#if tink_state.debug
  class DependencyTree {

    public final source:Observable<Dynamic>;
    public final dependencies:haxe.ds.ReadOnlyArray<DependencyTree>;

    public function new(source:ObservableObject<Dynamic>) {
      this.source = source;
      this.dependencies = [for (dep in source.getDependencies()) dep.dependencyTree()];
    }

    function print(prefix:String, buf:StringBuf) {

      buf.add(prefix);
      buf.add(source.toString());

      prefix += '  ';
      for (d in dependencies) {
        buf.add('\n');
        print(prefix, buf);
      }
    }

    public function toString() {
      var buf = new StringBuf();
      print('', buf);
      return buf.toString();
    }
  }
#end

private class ConstObservable<T> implements ObservableObject<T> {
  final value:T;
  final revision = new Revision();

  public function getRevision()
    return revision;

  public function new(value, ?toString:()->String #if tink_state.debug , ?pos:haxe.PosInfos #end) {
    this.value = value;
    #if tink_state.debug
    this._toString =
      switch toString {
        case null: () -> 'Constant[$value](${pos.fileName}:${pos.lineNumber}';
        case v: v;
      }
    #end
  }

  #if tink_state.debug
  final _toString:()->String;
  public function toString()
    return _toString();
  #end

  public function getValue()
    return value;

  public function isValid()
    return true;

  public function getComparator()
    return null;

  #if tink_state.debug
  public function getObservers()
    return EMPTY.iterator();

  public function getDependencies()
    return [].iterator();
  #end

  static final EMPTY = [];

  public function onInvalidate(i:Invalidatable):CallbackLink
    return null;
}

private class SimpleObservable<T> extends Invalidator implements ObservableObject<T> {

  var _poll:Void->Measurement<T>;
  var _cache:Measurement<T> = null;
  var comparator:Comparator<T>;

  public function new(poll, ?comparator, ?toString #if tink_state.debug , ?pos #end) {
    super(toString #if tink_state.debug , pos #end);
    this._poll = poll;
    this.comparator = comparator;
  }

  public function isValid()
    return _cache != null;

  public function getComparator()
    return comparator;

  function reset(_) {
    _cache = null;
    fire();
  }

  function poll() {
    var count = 0;

    while (_cache == null)
      if (++count == 100)
        throw "polling did not conclude after 100 iterations";
      else {
        _cache = _poll();
        _cache.becameInvalid.handle(reset);
      }

    return _cache;
  }

  public function getValue()
    return poll().value;

  #if tink_state.debug
  public function getDependencies()
    return [].iterator();
  #end
}

private abstract Transform<T, R>(T->R) {
  inline function new(f)
    this = f;

  public inline function apply(value:T):R
    return this(value);

  @:from static function naiveAsync<T, R>(f:T->Promise<R>):Transform<Promised<T>, Promise<R>>
    return new Transform(function (p:Promised<T>):Promise<R> return switch p {
      case Failed(e): e;
      case Loading: new Future(function (_) return null);
      case Done(v): f(v);
    });

  @:from static function naive<T, R>(f:T->R):Transform<Promised<T>, Promised<R>>
    return new Transform(function (p) return switch p {
      case Failed(e): Failed(e);
      case Loading: Loading;
      case Done(v): Done(f(v));
    });

  @:from static function plain<T, R>(f:T->R):Transform<T, R>
    return new Transform(f);
}

@:access(tink.state.Observable)
class ObservableTools {

  static public function deliver<T>(o:Observable<Promised<T>>, initial:T, ?failed:Error->T->T):Observable<T>
    return Observable.lift(o).map(function (p) return switch p {
      case Done(v): initial = v;
      case Loading: initial;
      case Failed(e): if (failed != null) initial = failed(e, initial) else initial;
    });

  static public function flatten<T>(o:Observable<Observable<T>>)
    return Observable.auto(() -> Observable.lift(o).value.value);

}