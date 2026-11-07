unit Atlas.Common.Editing.MethodWithoutSelf.Texts;

// Texte von „Methode ohne Self“ (#686) in beiden Sprachen (#1458): Gründe, warum eine Umwandlung nicht geht,
// Warnungen und Titel der Aktionen. Eigene Unit, damit Atlas.Common.Editing.MethodWithoutSelf unter der
// Grenze von metric-unit-length bleibt.

interface

uses
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte von „Methode ohne Self“ in beiden Sprachen (#1458).</summary>
  TEditingMethodWithoutSelfText = (NoMethod, MethodOfAGenericOr, NoTree, NoMethodWithABody,
    ConstructorDestructorOrOperator, AlreadyAClassMethod, UnsupportedForm, ClassNotInTheFile, Overloaded,
    DeclarationMissing, UnsupportedParameters, NameNotFoundInThe, BelongsToTheInterface, AccessorOfTheProperty,
    VirtualOverrideOrMessage, CalledViaRtti, IsAnEventInThe, NamesCannotBeResolved, IsUnknown, IsUsedAsAMethod,
    TheHeaderNamesAType,
    AlreadyExistsInTheUnit, IsWritten, InAnAnonymousMethod, FirstParameterIs, FirstParameterWithoutTypeOr,
    FirstParameterHasNoSimple, IsNoLongerEvaluated, AccessorOfAProperty, UseNotRecognized, StaysWithoutStaticTheBody,
    OtherUnitsCallItBut, FirstUseNotInA, TheHelperIsInThe, IsAlreadyVisibleFor, EndOfTheHelperNot, EndOfTheHelperIs,
    AfterTheChangeNoLonger, BecomesAFreeRoutine, MovesToRecordHelperFor, BecomesAClassMethod, ChangedCalls,
    MethodWithoutBody, MethodOfAnInterface, UsedAsAMethodPointer, InheritedCall, CallWithoutArguments, NestedCalls,
    Line, Line2, UsesInherited, UsesWith, UsesSelf, UsesText, UsesStrict, ConvertToClassMethod,
    ConvertToClassMethodCalls, ConvertToStandaloneRoutine, MoveToRecordHelperFor);

const
  cTexts: array[TEditingMethodWithoutSelfText] of TAtlasText = (
    (De: 'keine Methode'; En: 'no method'),
    (De: 'Methode eines generischen oder verschachtelten Typs'; En: 'method of a generic or nested type'),
    (De: 'kein Baum'; En: 'no tree'),
    (De: 'keine Methode mit Rumpf in dieser Unit'; En: 'no method with a body in this unit'),
    (De: 'Konstruktor, Destruktor oder Operator'; En: 'constructor, destructor or operator'),
    (De: 'schon eine class-Methode'; En: 'already a class method'),
    (De: 'nicht unterstützte Form'; En: 'unsupported form'),
    (De: 'Klasse %s nicht in der Datei'; En: 'Class %s not in the file'),
    (De: 'überladen'; En: 'overloaded'),
    (De: 'Deklaration fehlt'; En: 'declaration missing'),
    (De: 'nicht unterstützte Parameter'; En: 'unsupported parameters'),
    (De: 'Name im Kopf nicht gefunden'; En: 'name not found in the header'),
    (De: 'gehört zum Interface '; En: 'belongs to the interface '),
    (De: 'Zugriffsmethode der Property '; En: 'accessor of the property '),
    (De: 'virtuell, override oder Botschaft'; En: 'virtual, override or message'),
    (De: 'mit Attribut oder published, Aufruf über RTTI'; En: 'with attribute or published, called via RTTI'),
    (De: 'steht als Ereignis in der Formulardatei'; En: 'is an event in the form file'),
    (De: 'Namen nicht auflösbar'; En: 'names cannot be resolved'),
    (De: '%s ist unbekannt (%s)'; En: '%s is unknown (%s)'),
    (De: 'wird als Methodenzeiger benutzt (%s)'; En: 'is used as a method pointer (%s)'),
    (De: 'der Kopf nennt einen Typ der Klasse'; En: 'the header names a type of the class'),
    (De: ' gibt es schon in der Unit'; En: ' already exists in the unit'),
    (De: ' wird geschrieben'; En: ' is written'),
    (De: ' in einer anonymen Methode'; En: ' in an anonymous method'),
    (De: 'erster Parameter ist '; En: 'first parameter is '),
    (De: 'erster Parameter ohne Typ oder mit Vorgabewert'; En: 'first parameter without type or with default value'),
    (De: 'erster Parameter hat keinen einfachen Typ'; En: 'first parameter has no simple type'),
    (De: '%s: %s wird nicht mehr ausgewertet.'; En: '%s: %s is no longer evaluated.'),
    (De: 'Zugriffsmethode einer Property'; En: 'accessor of a property'),
    (De: 'Verwendung nicht erkannt'; En: 'use not recognized'),
    (De: '%s bleibt ohne static: Der Rumpf ruft class-Methoden ohne static auf.';
     En: '%s stays without static: the body calls class methods without static.'),
    (De: 'andere Units rufen auf, die Klasse steht aber im implementation-Teil';
     En: 'other units call it, but the class is in the implementation part'),
    (De: 'erste Verwendung nicht in einer Routine'; En: 'first use not in a routine'),
    (De: 'der Helper %s steht im implementation-Teil, andere Units rufen aber auf';
     En: 'the helper %s is in the implementation part, but other units call it'),
    (De: 'Für %s ist schon %s sichtbar. Nur ein Helper je Typ wirkt: Wo %s gilt, sind die Methoden von %s nicht mehr ' +
      'erreichbar.';
     En: '%1:s is already visible for %0:s. Only one helper per type takes effect: where %2:s applies, the methods ' +
      'of %3:s are no longer reachable.'),
    (De: 'Ende des Helpers nicht gefunden'; En: 'End of the helper not found'),
    (De: 'end des Helpers steht nicht allein in der Zeile'; En: 'end of the helper is not alone on its line'),
    (De: 'Nach der Änderung parst %s nicht mehr fehlerfrei (Zeile %d: %s)';
     En: 'After the change %s no longer parses without errors (line %d: %s)'),
    (De: '%s.%s wird freie Routine'; En: '%s.%s becomes a free routine'),
    (De: '%s.%s wandert nach %s (record helper for %s)'; En: '%s.%s moves to %s (record helper for %s)'),
    (De: '%s.%s wird class-Methode'; En: '%s.%s becomes a class method'),
    (De: ', %d geänderte Aufrufe.'; En: ', %d changed calls.'),
    (De: 'Methode ohne Rumpf'; En: 'method without body'),
    (De: 'Methode eines Interfaces (%s)'; En: 'method of an interface (%s)'),
    (De: 'als Methodenzeiger benutzt'; En: 'used as a method pointer'),
    (De: 'inherited-Aufruf'; En: 'inherited call'),
    (De: 'Aufruf ohne Argumente'; En: 'call without arguments'),
    (De: ': verschachtelte Aufrufe'; En: ': nested calls'),
    (De: 'Zeile %d'; En: 'Line %d'),
    (De: '%s, Zeile %d'; En: '%s, line %d'),
    (De: 'benutzt inherited'; En: 'uses inherited'),
    (De: 'benutzt with'; En: 'uses with'),
    (De: 'benutzt Self (%s)'; En: 'uses Self (%s)'),
    (De: 'benutzt %s (%s)'; En: 'uses %s (%s)'),
    (De: 'benutzt %s (strict)'; En: 'uses %s (strict)'),
    (De: 'In class-Methode umwandeln'; En: 'Convert to class method'),
    (De: 'In class-Methode umwandeln, Aufrufe über %s'; En: 'Convert to class method, calls via %s'),
    (De: 'In freie Routine umwandeln'; En: 'Convert to standalone routine'),
    (De: 'In Record-Helper für %s verschieben'; En: 'Move to record helper for %s'));

{$SCOPEDENUMS OFF}

implementation

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.MethodWithoutSelf', cTexts);

end.
