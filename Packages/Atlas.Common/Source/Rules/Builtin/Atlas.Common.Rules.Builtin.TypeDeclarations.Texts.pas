unit Atlas.Common.Rules.Builtin.TypeDeclarations.Texts;

// Texte der Regeln zu Typdeklarationen in beiden Sprachen (#1458). Eigene Unit, damit
// Atlas.Common.Rules.Builtin.TypeDeclarations unter der Grenze von metric-unit-length bleibt.

interface

uses
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte von Atlas.Common.Rules.Builtin.TypeDeclarations in beiden Sprachen (#1458).</summary>
  TTypeDeclarationsText = (MessageTitle, PassAsVar, InsertSignature, MessageParam, MessageNumber, MessageHandled,
    InterfaceTitle, RecordKind, EnumKind, ClassKind, NotInterface, AlreadyListed, ClauseNotAllowed,
    PropertyRedeclared, NoFields, DirectiveNotAllowed, ImplementsTitle, ImplementsType, GetterRegister, GetterNot,
    ImplementsIndex, AlreadyImplemented, ImplementsClassOnly, ImplementsReadable, MethodResolution, ConventionTitle,
    RemoveName, CtorRegister, PublishedRegister, VarargsWin32, VarargsCdecl, SetCdecl, DispTitle, DispAncestor,
    RemoveAncestor, DispGuid, InsertGuid, DispMethodDirective, DispDirective);

const
  cTexts: array[TTypeDeclarationsText] of TAtlasText = (
    (De: 'message-Methode falsch deklariert'; En: 'message method declared incorrectly'),
    (De: 'Parameter %s als var übergeben'; En: 'Pass parameter %s as var'),
    (De: 'Signatur %s einsetzen'; En: 'Insert signature %s'),
    (De: 'Die message-Methode %s braucht genau einen var-Parameter (wie E2138).';
     En: 'The message method %s needs exactly one var parameter (like E2138).'),
    (De: 'Die Nachrichtennummer %s von %s muss mindestens 1 sein (wie E2139).';
     En: 'The message number %s of %s must be at least 1 (like E2139).'),
    (De: '%s wird schon von %s behandelt (wie E2140).'; En: '%s is already handled by %s (like E2140).'),
    (De: 'Unzulässige Deklaration in einem Interface'; En: 'Invalid declaration in an interface'),
    (De: 'ein Record'; En: 'a record'),
    (De: 'eine Aufzählung'; En: 'an enumeration'),
    (De: 'eine Klasse'; En: 'a class'),
    (De: '%s ist %s und kein Interface (wie E2205).'; En: '%s is %s and not an interface (like E2205).'),
    (De: '%s steht schon in der Liste der Interfaces (wie E2208).';
     En: '%s is already in the list of interfaces (like E2208).'),
    (De: 'Die Klausel %s ist in Interfaces nicht erlaubt (wie E2207).';
     En: 'The clause %s is not allowed in interfaces (like E2207).'),
    (De: 'Die Property %s ist schon in %s deklariert; Interfaces dürfen Properties nicht ohne Typ neu aufführen (wie ' +
      'E2206).';
     En: 'The property %s is already declared in %s; interfaces must not list properties again without type (like ' +
      'E2206).'),
    (De: 'Interfaces dürfen keine Felder haben (wie E2209).'; En: 'Interfaces must not have fields (like E2209).'),
    (De: 'Die Direktive %s ist in Interfaces nicht erlaubt (wie E2210).';
     En: 'The directive %s is not allowed in interfaces (like E2210).'),
    (De: 'implements-Klausel unzulässig'; En: 'implements clause invalid'),
    (De: 'implements ist nur an Properties mit Klassen- oder Interface-Typ erlaubt, %s ist keiner (wie E2259).';
     En: 'implements is only allowed on properties with class or interface type, %s is none (like E2259).'),
    (De: 'Der Getter %s einer implements-Property darf nicht %s sein, nur register (wie E2262).';
     En: 'The getter %s of an implements property must not be %s, only register (like E2262).'),
    (De: 'Der Getter %s einer implements-Property darf nicht %s sein (wie E2263 und E2148).';
     En: 'The getter %s of an implements property must not be %s (like E2263 and E2148).'),
    (De: 'implements ist nicht zusammen mit index erlaubt (wie E2260).';
     En: 'implements is not allowed together with index (like E2260).'),
    (De: '%s wird schon von %s per implements umgesetzt (wie E2257).';
     En: '%s is already implemented by %s via implements (like E2257).'),
    (De: 'implements ist nur in Klassen erlaubt (wie E2258).';
     En: 'implements is only allowed in classes (like E2258).'),
    (De: 'implements braucht eine lesbare Property (wie E2261).';
     En: 'implements needs a readable property (like E2261).'),
    (De: 'Für %s gibt es die implements-Property %s; Methodenzuordnungen sind dann nicht erlaubt (wie E2264).';
     En: 'For %s there is the implements property %s; method resolutions are then not allowed (like E2264).'),
    (De: 'Aufrufkonvention passt nicht'; En: 'Calling convention does not fit'),
    (De: '%s entfernen'; En: 'Remove %s'),
    (De: 'Konstruktoren und Destruktoren brauchen register, nicht %s (wie E2236).';
     En: 'Constructors and destructors need register, not %s (like E2236).'),
    (De: 'Der %s %s der published-Property %s braucht register, nicht %s (wie E2270).';
     En: 'The %s %s of the published property %s needs register, not %s (like E2270).'),
    (De: 'varargs ist unter Win32 nur an external-Routinen mit cdecl erlaubt (wie E2277).';
     En: 'varargs is only allowed under Win32 on external routines with cdecl (like E2277).'),
    (De: 'varargs ist nur mit cdecl erlaubt (wie %s).'; En: 'varargs is only allowed with cdecl (like %s).'),
    (De: 'cdecl setzen'; En: 'Set cdecl'),
    (De: 'Unzulässige dispinterface-Deklaration'; En: 'Invalid dispinterface declaration'),
    (De: 'Ein dispinterface kann keinen Vorfahren haben (wie E2228).';
     En: 'A dispinterface cannot have an ancestor (like E2228).'),
    (De: 'Vorfahren entfernen'; En: 'Remove ancestor'),
    (De: 'Das dispinterface %s braucht eine GUID (wie E2229).'; En: 'The dispinterface %s needs a GUID (like E2229).'),
    (De: 'GUID einfügen'; En: 'Insert GUID'),
    (De: 'Methoden eines dispinterface dürfen keine Direktive %s haben (wie E2230).';
     En: 'Methods of a dispinterface must not have the directive %s (like E2230).'),
    (De: 'Die Direktive %s ist in einem dispinterface nicht erlaubt (wie E2231).';
     En: 'The directive %s is not allowed in a dispinterface (like E2231).'));

{$SCOPEDENUMS OFF}

implementation

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.TypeDeclarations', cTexts);

end.
