unit Atlas.Common.Editing.TypeAlias.Texts;

// Texte von „Typalias einführen“ in beiden Sprachen (#1458). Eigene Unit, damit Atlas.Common.Editing.TypeAlias
// unter der Grenze von metric-unit-length bleibt.

interface

uses
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte von Atlas.Common.Editing.TypeAlias in beiden Sprachen (#1458).</summary>
  TEditingTypeAliasText = (AfterTheChangeNoLonger, IsNotAValidIdentifier, UsesTypesFromTheImplementation,
    TheUnitHasNoInterface, TheNameIsAlreadyTaken, IsNotDeclaredYetBefore, GetsAForwardDeclarationBefore,
    EqualExpressionsRemainNotUsed, IsInTheImplementationPart, ThereIsNoTypeAlias, IsGeneric, IsNotAnAlias,
    TypeIsADistinctType, NoTree, UsesForCannotBeAdded, UsesKeepParameterResultProperty, NoUseOfCanBe,
    IsNotUsedAnywhere, IsReplacedByPlacesIn, TheAliasIsRemoved, InPlacesInFiles, Line, ImplementationPart,
    InterfacePart, IntroduceTypeAlias, IntroduceTypeAliasThisPlace, IntroduceTypeAliasInThe, IntroduceTypeAliasInThe2,
    ResolveAlias, NoTypeAliasTheExpression, AtlasWritesXYAssignment, ThereIsNoTypeExpression);

const
  cTexts: array[TEditingTypeAliasText] of TAtlasText = (
    (De: 'Nach der Änderung parst %s nicht mehr fehlerfrei (Zeile %d: %s)';
     En: 'After the change %s no longer parses without errors (line %d: %s)'),
    (De: '"%s" ist kein gültiger Bezeichner'; En: '"%s" is not a valid identifier'),
    (De: '%s nutzt Typen aus dem implementation-Teil; ersetzt wird nur in dieser Unit';
     En: '%s uses types from the implementation part; it is replaced only in this unit'),
    (De: 'Die Unit hat keinen interface-Teil'; En: 'The unit has no interface part'),
    (De: 'Der Name %s ist schon vergeben'; En: 'The name %s is already taken'),
    (De: '%s ist vor der ersten Verwendung von %s noch nicht deklariert';
     En: '%s is not declared yet before the first use of %s'),
    (De: '%s bekommt eine Vorwärtsdeklaration vor dem Alias'; En: '%s gets a forward declaration before the alias'),
    (De: '%s: %d gleiche Ausdrücke bleiben (%s nicht eingebunden oder %s dort vergeben)';
     En: '%s: %d equal expressions remain (%s not used or %s taken there)'),
    (De: '%s steht im implementation-Teil; andere Units sehen ihn nicht';
     En: '%s is in the implementation part; other units do not see it'),
    (De: 'Hier steht kein Typ-Alias'; En: 'There is no type alias here'),
    (De: '%s ist generisch'; En: '%s is generic'),
    (De: '%s ist kein Alias'; En: '%s is not an alias'),
    (De: '%s = type … ist ein eigener Typ; Auflösen würde die Bedeutung ändern';
     En: '%s = type … is a distinct type; resolving it would change the meaning'),
    (De: 'kein Baum'; En: 'no tree'),
    (De: '%s: uses für %s lässt sich nicht ergänzen'; En: '%s: uses for %s cannot be added'),
    (De: '%d Verwendungen behalten %s (Parameter, Ergebnis, Property, Typargument, Ausdruck oder eine Unit, die den ' +
      'Typ nicht sieht); der Alias bleibt';
     En: '%d uses keep %s (parameter, result, property, type argument, expression or a unit that does not see the ' +
      'type); the alias stays'),
    (De: 'Keine Verwendung von %s lässt sich ersetzen'; En: 'No use of %s can be replaced'),
    (De: '%s wird nirgends verwendet'; En: '%s is not used anywhere'),
    (De: '%s wird durch %s ersetzt, %d Stellen in %d Dateien'; En: '%s is replaced by %s, %d places in %d files'),
    (De: '; der Alias entfällt.'; En: '; the alias is removed.'),
    (De: '%s = %s; im %s, %d Stellen in %d Dateien.'; En: '%s = %s; in %s, %d places in %d files.'),
    (De: '%s, Zeile %d'; En: '%s, line %d'),
    (De: 'implementation-Teil'; En: 'implementation part'),
    (De: 'interface-Teil'; En: 'interface part'),
    (De: 'Typ-Alias einführen (%s)'; En: 'Introduce type alias (%s)'),
    (De: 'Typ-Alias einführen, nur diese Stelle (%s)'; En: 'Introduce type alias, this place only (%s)'),
    (De: 'Typ-Alias einführen, in der Unit (%s)'; En: 'Introduce type alias, in the unit (%s)'),
    (De: 'Typ-Alias einführen, im Projekt (%s)'; En: 'Introduce type alias, in the project (%s)'),
    (De: 'Alias auflösen (%s)'; En: 'Resolve alias (%s)'),
    (De: 'Kein Typ-Alias: Der Ausdruck nutzt den generischen Parameter %s, und Delphi kennt keine generischen ' +
      'Aliase. Möglich wäre eine Ableitung TName<T> = class(TBasis<T>), die Atlas nicht selbst anlegt.';
     En: 'No type alias: the expression uses the generic parameter %s, and Delphi has no generic aliases. A ' +
      'descendant TName<T> = class(TBase<T>) would be possible, which Atlas does not create itself.'),
    (De: 'Atlas schreibt X = Y: zuweisungsverträglich mit dem Ausdruck. X = type Y wäre ein eigener, nicht ' +
      'verträglicher Typ.';
     En: 'Atlas writes X = Y: assignment compatible with the expression. X = type Y would be a distinct, ' +
      'incompatible type.'),
    (De: 'Hier steht kein Typausdruck, für den ein Alias lohnt';
     En: 'There is no type expression here that is worth an alias'));

{$SCOPEDENUMS OFF}

implementation

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.TypeAlias', cTexts);

end.
