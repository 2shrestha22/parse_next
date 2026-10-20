// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'memo.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Memo {

 String get text;@ParseKey('due_at') DateTime? get dueAt; List<String> get tags; Mood? get mood;
/// Create a copy of Memo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MemoCopyWith<Memo> get copyWith => _$MemoCopyWithImpl<Memo>(this as Memo, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as Memo;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Memo&&(identical(other.text, _this.text) || other.text == _this.text)&&(identical(other.dueAt, _this.dueAt) || other.dueAt == _this.dueAt)&&const DeepCollectionEquality().equals(other.tags, _this.tags)&&(identical(other.mood, _this.mood) || other.mood == _this.mood));
}


@override
int get hashCode {
  final _this = this as Memo;
  return Object.hash(runtimeType,_this.text,_this.dueAt,const DeepCollectionEquality().hash(_this.tags),_this.mood);
}

@override
String toString() {
  final _this = this as Memo;
  return 'Memo(text: ${_this.text}, dueAt: ${_this.dueAt}, tags: ${_this.tags}, mood: ${_this.mood})';
}


}

/// @nodoc
abstract mixin class $MemoCopyWith<$Res>  {
  factory $MemoCopyWith(Memo value, $Res Function(Memo) _then) = _$MemoCopyWithImpl;
@useResult
$Res call({
 String text,@ParseKey('due_at') DateTime? dueAt, List<String> tags, Mood? mood
});




}
/// @nodoc
class _$MemoCopyWithImpl<$Res>
    implements $MemoCopyWith<$Res> {
  _$MemoCopyWithImpl(this._self, this._then);

  final Memo _self;
  final $Res Function(Memo) _then;

/// Create a copy of Memo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? text = null,Object? dueAt = freezed,Object? tags = null,Object? mood = freezed,}) {
  return _then(Memo(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,dueAt: freezed == dueAt ? _self.dueAt : dueAt // ignore: cast_nullable_to_non_nullable
as DateTime?,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,mood: freezed == mood ? _self.mood : mood // ignore: cast_nullable_to_non_nullable
as Mood?,
  ));
}

}


/// Adds pattern-matching-related methods to [Memo].
extension MemoPatterns on Memo {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Memo value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Memo() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Memo value)  $default,){
final _that = this;
switch (_that) {
case _Memo():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Memo value)?  $default,){
final _that = this;
switch (_that) {
case _Memo() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String text, @ParseKey('due_at')  DateTime? dueAt,  List<String> tags,  Mood? mood)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Memo() when $default != null:
return $default(_that.text,_that.dueAt,_that.tags,_that.mood);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String text, @ParseKey('due_at')  DateTime? dueAt,  List<String> tags,  Mood? mood)  $default,) {final _that = this;
switch (_that) {
case _Memo():
return $default(_that.text,_that.dueAt,_that.tags,_that.mood);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String text, @ParseKey('due_at')  DateTime? dueAt,  List<String> tags,  Mood? mood)?  $default,) {final _that = this;
switch (_that) {
case _Memo() when $default != null:
return $default(_that.text,_that.dueAt,_that.tags,_that.mood);case _:
  return null;

}
}

}

/// @nodoc


class _Memo implements Memo {
  const _Memo({required this.text, @ParseKey('due_at') this.dueAt, required  List<String> tags, this.mood}): _tags = tags;
  

@override final  String text;
@override@ParseKey('due_at') final  DateTime? dueAt;
 final  List<String> _tags;
@override List<String> get tags {
  if (_tags is EqualUnmodifiableListView) return _tags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tags);
}

@override final  Mood? mood;

/// Create a copy of Memo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MemoCopyWith<_Memo> get copyWith => __$MemoCopyWithImpl<_Memo>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Memo&&(identical(other.text, text) || other.text == text)&&(identical(other.dueAt, dueAt) || other.dueAt == dueAt)&&const DeepCollectionEquality().equals(other.tags, _tags)&&(identical(other.mood, mood) || other.mood == mood));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text,dueAt,const DeepCollectionEquality().hash(_tags),mood);
}

@override
String toString() {
    return 'Memo(text: $text, dueAt: $dueAt, tags: $tags, mood: $mood)';
}


}

/// @nodoc
abstract mixin class _$MemoCopyWith<$Res> implements $MemoCopyWith<$Res> {
  factory _$MemoCopyWith(_Memo value, $Res Function(_Memo) _then) = __$MemoCopyWithImpl;
@override @useResult
$Res call({
 String text,@ParseKey('due_at') DateTime? dueAt, List<String> tags, Mood? mood
});




}
/// @nodoc
class __$MemoCopyWithImpl<$Res>
    implements _$MemoCopyWith<$Res> {
  __$MemoCopyWithImpl(this._self, this._then);

  final _Memo _self;
  final $Res Function(_Memo) _then;

/// Create a copy of Memo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? text = null,Object? dueAt = freezed,Object? tags = null,Object? mood = freezed,}) {
  return _then(_Memo(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,dueAt: freezed == dueAt ? _self.dueAt : dueAt // ignore: cast_nullable_to_non_nullable
as DateTime?,tags: null == tags ? _self._tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,mood: freezed == mood ? _self.mood : mood // ignore: cast_nullable_to_non_nullable
as Mood?,
  ));
}


}

// dart format on
