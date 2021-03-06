package tink.state.internal;

class SignalObservable<X, T> implements ObservableObject<T> {
  var valid = false;
  var value:Null<T>;
  var revision = new Revision();

  public function getRevision()
    return revision;

  final get:Void->T;

  final observers = new Map();
  final changed:Signal<Noise>;

  public function new(get, changed:Signal<Noise>, ?toString:(id:Int)->String #if tink_state.debug , ?pos:haxe.PosInfos #end) {
    this.get = get;
    this.changed = changed;
    this.changed.handle(function (_) if (valid) {
      revision = new Revision();
      valid = false;
    });
    #if tink_state.debug
      this._toString = switch toString {
        case null: id -> 'SignalObservable#$id(${pos.fileName}:${pos.lineNumber})';
        case v: v;
      }
    #end
  }

  #if tink_state.debug
  static var counter = 0;
  var id = counter++;
  final _toString:(id:Int)->String;
  @:keep public function toString()
    return _toString(id);
  #end

  public function getValue():T
    return
      if (valid) value;
      else {
        valid = true;
        value = get();
      }

  public function isValid():Bool
    return valid;

  public function getComparator():Comparator<T>
    return null;

  public function onInvalidate(i:Invalidatable):CallbackLink
    return
      if (observers.get(i)) null;
      else {
        observers.set(i, true);
        changed.handle(i.invalidate);
      }

  #if tink_state.debug
  public function getObservers()
    return observers.keys();

  public function getDependencies()
    return [].iterator();
  #end
}