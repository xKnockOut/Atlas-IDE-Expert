unit Atlas.Common.Editing.ExtractInterface;

// „Interface aus Klasse herauslösen“ (#664), Gegenstück zu „Interface
// implementieren“ (#466):
//   - Kandidaten: public- und published-Methoden und -Properties der Klasse.
//     Vorab gewählt sind alle public-Methoden. Konstruktoren, Destruktoren,
//     Klassenmethoden, Operatoren und generische Methoden kann ein Interface
//     nicht enthalten; sie stehen mit Grund in der Liste, sind aber nicht
//     wählbar. Ereignis-Properties (Typ eines Methodenzeigers) und Properties
//     sind wählbar, aber nicht vorab gewählt; Klassen-Properties und
//     Properties ohne Typ (nur Sichtbarkeit geändert) nicht wählbar.
//   - Name: Vorschlag I + Klassenname ohne T, gültiger Bezeichner, kein
//     anderer Name im Gültigkeitsbereich (Rückfrage über TNameInUse).
//   - Interface: neue GUID, die Methoden mit ihrer Signatur (Standardwerte,
//     overload, const/var/out und Aufrufkonventionen bleiben, virtual,
//     override, reintroduce, abstract, inline, message usw. entfallen), die
//     Properties mit Getter und Setter (stored, Standardwerte, nodefault und
//     implements entfallen) und die Doku-Kommentare. Zugriffsmethoden einer
//     gewählten Property kommen mit ins Interface. Liest oder schreibt eine
//     Property ein Feld, legt Atlas in der Klasse GetX/SetX (private) an und
//     stellt die Property darauf um.
//   - Klasse: Das Interface kommt in die Vorfahrenliste. Ohne Vorfahr oder mit
//     TObject wird TInterfacedObject der Vorfahr; hat die Klasse schon
//     Interfaces, implementiert sie IInterface schon. Sonst prüft
//     TInterfaceSupport die Vorfahrenkette; ohne IInterface-Implementierung
//     bzw. unbekannt gibt es einen Hinweis für die Vorschau.
//   - Ziel: dieselbe Unit (direkt vor der Klasse samt Doku und Attributen)
//     oder eine andere Unit. Dafür liefert der Plan den Text des Interfaces
//     und die Namen der Typen in den Signaturen; uses, neue Unit und Projekt
//     macht Atlas.Common.Lsp.ExtractInterface.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.ClassLayout;

type
  {$SCOPEDENUMS ON}
  TInterfaceSupport = (Yes, No, Unknown);
  TExtractCandidateKind = (Method, Property_);
  {$SCOPEDENUMS OFF}

  /// <summary>Vorfahren einer Klasse (erster Eintrag = Vorfahr); False, wenn die Klasse unbekannt ist.</summary>
  TClassAncestorsLookup = reference to function(const AClassName: string; out AAncestors: TArray<string>): Boolean;
  /// <summary>Ist AName im Gültigkeitsbereich der Klasse schon vergeben?</summary>
  TNameInUse = reference to function(const AName: string): Boolean;
  /// <summary>Ist ATypeName ein Methodenzeiger (procedure … of object, reference to)?</summary>
  TIsMethodPointer = reference to function(const ATypeName: string): Boolean;

  /// <summary>Rückfragen an den Aufrufer; jede darf nil sein.</summary>
  TExtractInterfaceLookups = record
    Ancestors: TClassAncestorsLookup;
    NameInUse: TNameInUse;
    IsMethodPointer: TIsMethodPointer;
    class function Create(const AAncestors: TClassAncestorsLookup; const ANameInUse: TNameInUse;
      const AIsMethodPointer: TIsMethodPointer): TExtractInterfaceLookups; static;
  end;

  TExtractCandidate = record
    /// <summary>Index des Mitglieds in TClassLayout.Members.</summary>
    Id: Integer;
    Name: string;
    Kind: TExtractCandidateKind;
    /// <summary>Kopf ohne Direktiven bzw. Property-Deklaration.</summary>
    Display: string;
    Visibility: TClassVisibility;
    Checked: Boolean;
    Enabled: Boolean;
    /// <summary>Warum nicht wählbar; '' sonst.</summary>
    Reason: string;
  end;

  TExtractInterfaceInfo = record
    ClassName: string;
    SuggestedName: string;
    Candidates: TArray<TExtractCandidate>;
    /// <summary>Hinweise vorab (Vorfahr ohne IInterface).</summary>
    Notes: TArray<string>;
  end;

  TExtractInterfaceRequest = record
    Name: string;
    /// <summary>Ids der gewählten Kandidaten.</summary>
    Members: TArray<Integer>;
    /// <summary>GUID samt geschweiften Klammern.</summary>
    Guid: string;
    /// <summary>Das Interface steht in derselben Unit (sonst liefert der Plan nur seinen Text).</summary>
    SameUnit: Boolean;
  end;

  TExtractInterfacePlan = record
    ClassName: string;
    InterfaceName: string;
    /// <summary>Deklaration des Interfaces ohne Einrückung, Zeilen mit #10, ohne Umbruch am Ende.</summary>
    Declaration: string;
    /// <summary>Änderungen an der Unit der Klasse (mit SameUnit samt dem Interface).</summary>
    Edits: TArray<TTextEdit>;
    /// <summary>Erste Bezeichner der Typen in den Signaturen (für uses einer anderen Ziel-Unit).</summary>
    TypeNames: TArray<string>;
    /// <summary>Methoden im Interface (einschließlich mitgenommener Zugriffsmethoden).</summary>
    Methods: TArray<string>;
    Warnings: TArray<string>;
    /// <summary>Die Klasse steht im interface-Teil ihrer Unit; Offset ihrer Deklaration.</summary>
    InInterface: Boolean;
    ClassOffset: Integer;
  end;

  TExtractInterface = class
  public const
    Kind = 'refactor.extract';
  public
    /// <summary>I + Klassenname ohne führendes T (TKunde → IKunde).</summary>
    class function DefaultName(const AClassName: string): string; static;
    /// <summary>Klasse auf der Kopfzeile ALine; nil ohne.</summary>
    class function ClassAt(ATree: TSyntaxTree; ALine: Integer): TSyntaxNode; static;
    /// <summary>Implementiert eine Klasse mit Vorfahr AAncestor IInterface? Bekannte RTL-Klassen, Klassen mit
    /// Interfaces in der Vorfahrenliste und deren Nachfahren ja; die Kette bis TObject ohne solche nein.</summary>
    class function Supports(const AAncestor: string; const ALookup: TClassAncestorsLookup): TInterfaceSupport;
      static;
    /// <summary>Kandidaten und Vorschlag für die Klasse in ASource; False mit Grund ohne Klasse oder ohne
    /// Kandidaten.</summary>
    class function Prepare(const ASource: TClassSource; const ALookups: TExtractInterfaceLookups;
      out AInfo: TExtractInterfaceInfo; out AReason: string): Boolean; static;
    /// <summary>Änderungen für ARequest; False mit Grund (Name ungültig oder vergeben, nichts gewählt,
    /// Kandidat nicht wählbar).</summary>
    class function Plan(const ASource: TClassSource; const ARequest: TExtractInterfaceRequest;
      const ALookups: TExtractInterfaceLookups; out APlan: TExtractInterfacePlan; out AReason: string): Boolean;
      static;
    /// <summary>Änderung, die ADeclaration (aus dem Plan) samt "type" vor die implementation einer anderen Unit
    /// setzt; False ohne interface-Teil.</summary>
    class function InsertIntoUnit(ATree: TSyntaxTree; const AText, ADeclaration: string;
      out AEdit: TTextEdit): Boolean; static;
    /// <summary>Text einer neuen Unit mit dem Interface; AUses darf leer sein.</summary>
    class function NewUnitText(const AUnitName, ADeclaration: string; const AUses: TArray<string>;
      const ALineBreak: string): string; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TEditingExtractInterfaceText = (PropertyWithoutReadAndWrite, GenericMethodNotAllowedIn,
    DoesNotImplementIInterfaceLacks, WhetherImplementsIInterfaceIsNot, ThereIsNoClassAt, HasNoPublicOrPublished,
    TheClassHasChangedPlease, CannotGoIntoTheInterface, IsNotAValidIdentifier, NoMemberIsSelected,
    TheNameIsAlreadyTaken, GoesIntoTheInterfaceToo, TheUnitHasNoImplementation, PropertyWithoutTypeInherited,
    ConstructorText, DestructorText, ClassMethod, MessageHandler);

const
  cTexts: array[TEditingExtractInterfaceText] of TAtlasText = (
    (De: 'Property ohne read und write'; En: 'property without read and write'),
    (De: 'generische Methode (in Interfaces nicht erlaubt)'; En: 'generic method (not allowed in interfaces)'),
    (De: '%s implementiert IInterface nicht: %s fehlen _AddRef, _Release und QueryInterface (Referenzzählen).';
     En: '%s does not implement IInterface: %s lacks _AddRef, _Release and QueryInterface (reference counting).'),
    (De: 'Ob %s IInterface implementiert, ist nicht bekannt; sonst fehlen %s _AddRef, _Release und QueryInterface ' +
      '(Referenzzählen).';
     En: 'Whether %s implements IInterface is not known; otherwise %s lacks _AddRef, _Release and QueryInterface ' +
      '(reference counting).'),
    (De: 'An dieser Stelle steht keine Klasse.'; En: 'There is no class at this position.'),
    (De: '%s hat keine public- oder published-Methoden und -Properties für ein Interface.';
     En: '%s has no public or published methods and properties for an interface.'),
    (De: 'Die Klasse hat sich geändert; bitte die Aktion erneut aufrufen.';
     En: 'The class has changed; please call the action again.'),
    (De: '%s kann nicht ins Interface: %s.'; En: '%s cannot go into the interface: %s.'),
    (De: '"%s" ist kein gültiger Bezeichner.'; En: '"%s" is not a valid identifier.'),
    (De: 'Es ist kein Mitglied gewählt.'; En: 'No member is selected.'),
    (De: 'Der Name %s ist schon vergeben.'; En: 'The name %s is already taken.'),
    (De: '%s kommt als Zugriffsmethode von %s mit ins Interface.';
     En: '%s goes into the interface too, as accessor of %s.'),
    (De: 'Die Unit hat keinen implementation-Teil für die neuen Zugriffsmethoden.';
     En: 'The unit has no implementation part for the new accessors.'),
    (De: 'Property ohne Typ (geerbt)'; En: 'property without type (inherited)'),
    (De: 'Konstruktor'; En: 'constructor'),
    (De: 'Destruktor'; En: 'destructor'),
    (De: 'Klassenmethode'; En: 'class method'),
    (De: 'Botschaftsbehandlung'; En: 'message handler'));

{$SCOPEDENUMS OFF}

const
  /// <summary>Klassen der RTL, die IInterface implementieren.</summary>
  InterfacedRoots: array[0..6] of string = ('TInterfacedObject', 'TAggregatedObject', 'TContainedObject',
    'TComponent', 'TInterfacedPersistent', 'TInterfaceList', 'TAutoIntfObject');
  /// <summary>Direktiven, die ins Interface mitkommen.</summary>
  KeptDirectives: array[0..5] of string = ('overload', 'stdcall', 'safecall', 'cdecl', 'register', 'pascal');

function StripT(const AName: string): string;
begin
  Result := AName;
  if (Length(Result) > 1) and CharInSet(Result[1], ['T', 't']) and CharInSet(Result[2], ['A'..'Z']) then
  begin
    Result := Copy(Result, 2, MaxInt);
  end;
end;

{ TExtractInterfaceLookups }

class function TExtractInterfaceLookups.Create(const AAncestors: TClassAncestorsLookup; const ANameInUse: TNameInUse;
  const AIsMethodPointer: TIsMethodPointer): TExtractInterfaceLookups;
begin
  Result.Ancestors := AAncestors;
  Result.NameInUse := ANameInUse;
  Result.IsMethodPointer := AIsMethodPointer;
end;

{ TExtractInterface }

class function TExtractInterface.DefaultName(const AClassName: string): string;
begin
  Result := 'I' + StripT(AClassName);
end;

class function TExtractInterface.ClassAt(ATree: TSyntaxTree; ALine: Integer): TSyntaxNode;
begin
  Result := TClassLayout.DeclAt(ATree, ALine, False);
end;

/// <summary>Klassenname ohne generische Parameter und ohne Unit davor.</summary>
function BareClassName(const AName: string): string;
begin
  Result := AName;
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
  if Pos('.', Result) > 0 then
  begin
    Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
  end;
end;

/// <summary>Entscheidet für die Klasse AName allein, ob sie IInterface implementiert (True, Ergebnis in
/// ASupport); False mit ihrem Vorfahr AParent, wenn erst die Kette darüber es zeigt.</summary>
function SupportStep(const AName: string; const ALookup: TClassAncestorsLookup; var ASupport: TInterfaceSupport;
  out AParent: string): Boolean;
var
  mChain: TArray<string>;
begin
  Result := True;
  AParent := '';
  if MatchText(AName, InterfacedRoots) then
  begin
    ASupport := TInterfaceSupport.Yes;
  end
  else if SameText(AName, 'TObject') then
  begin
    ASupport := TInterfaceSupport.No;
  end
  else if not Assigned(ALookup) or not ALookup(AName, mChain) then
  begin
    ASupport := TInterfaceSupport.Unknown;
  end
  // Interfaces in der Liste: die Klasse implementiert IInterface selbst.
  else if Length(mChain) > 1 then
  begin
    ASupport := TInterfaceSupport.Yes;
  end
  else if mChain = nil then
  begin
    ASupport := TInterfaceSupport.No;
  end
  else
  begin
    AParent := BareClassName(mChain[0]);
    Result := False;
  end;
end;

class function TExtractInterface.Supports(const AAncestor: string;
  const ALookup: TClassAncestorsLookup): TInterfaceSupport;
var
  mName, mParent: string;
  mDepth: Integer;
begin
  Result := TInterfaceSupport.Unknown;
  mName := BareClassName(AAncestor);
  mDepth := 0;
  while (mDepth < 32) and not SupportStep(mName, ALookup, Result, mParent) do
  begin
    mName := mParent;
    Inc(mDepth);
  end;
end;

/// <summary>Öffentliche Methode, Property oder Operator?</summary>
function IsCandidate(const AMember: TClassMember): Boolean;
begin
  Result := (AMember.Visibility in [TClassVisibility.Public_, TClassVisibility.Published_]) and
    (AMember.IsMethod or (AMember.Kind = TClassMemberKind.Property_) or
    (AMember.Kind = TClassMemberKind.Other) and (AMember.Node.Kind = TSyntaxKind.RoutineHeader));
end;

/// <summary>Warum die Property nicht ins Interface kann; '' wenn sie kann.</summary>
function PropertyReason(const AMember: TClassMember): string;
begin
  Result := '';
  if AMember.IsClassMember then
  begin
    Result := 'Klassen-Property';
  end
  else if AMember.IsRedeclaration then
  begin
    Result := cTexts[TEditingExtractInterfaceText.PropertyWithoutTypeInherited].Text;
  end
  else if (AMember.ReadAccessor = '') and (AMember.WriteAccessor = '') then
  begin
    Result := cTexts[TEditingExtractInterfaceText.PropertyWithoutReadAndWrite].Text;
  end;
end;

/// <summary>Warum die Methode nicht ins Interface kann; '' wenn sie kann.</summary>
function MethodReason(const AMember: TClassMember): string;
begin
  case AMember.Kind of
    TClassMemberKind.Constructor_:
      Result := cTexts[TEditingExtractInterfaceText.ConstructorText].Text;
    TClassMemberKind.Destructor_:
      Result := cTexts[TEditingExtractInterfaceText.DestructorText].Text;
    TClassMemberKind.Other:
      Result := 'Operator';
  else
    Result := '';
    if AMember.IsClassMember then
    begin
      Result := cTexts[TEditingExtractInterfaceText.ClassMethod].Text;
    end
    else if AMember.IsGeneric then
    begin
      Result := cTexts[TEditingExtractInterfaceText.GenericMethodNotAllowedIn].Text;
    end
    else if AMember.HasDirective('message') then
    begin
      Result := cTexts[TEditingExtractInterfaceText.MessageHandler].Text;
    end;
  end;
end;

function CandidateOf(ALayout: TClassLayout; AIndex: Integer; const AIsMethodPointer: TIsMethodPointer):
  TExtractCandidate;
var
  mMember: TClassMember;
begin
  mMember := ALayout.Members[AIndex];
  Result := Default(TExtractCandidate);
  Result.Id := AIndex;
  Result.Name := mMember.Name;
  Result.Visibility := mMember.Visibility;
  if mMember.Kind = TClassMemberKind.Property_ then
  begin
    Result.Kind := TExtractCandidateKind.Property_;
    Result.Display := ALayout.Declaration(AIndex);
    Result.Reason := PropertyReason(mMember);
  end
  else
  begin
    Result.Kind := TExtractCandidateKind.Method;
    Result.Display := ALayout.Head(AIndex);
    Result.Reason := MethodReason(mMember);
  end;
  Result.Enabled := Result.Reason = '';
  Result.Checked := Result.Enabled and (Result.Kind = TExtractCandidateKind.Method) and
    (mMember.Visibility = TClassVisibility.Public_);
  // Ereignis-Properties sind wählbar, aber nicht vorab gewählt (wie alle Properties).
  if Result.Enabled and (Result.Kind = TExtractCandidateKind.Property_) and Assigned(AIsMethodPointer) and
    AIsMethodPointer(mMember.TypeName) then
  begin
    Result.Display := Result.Display + '  // Ereignis';
  end;
end;

function Candidates(ALayout: TClassLayout; const AIsMethodPointer: TIsMethodPointer): TArray<TExtractCandidate>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(ALayout.Members) do
  begin
    if IsCandidate(ALayout.Members[mIndex]) then
    begin
      Result := Result + [CandidateOf(ALayout, mIndex, AIsMethodPointer)];
    end;
  end;
end;

function AncestorNote(ALayout: TClassLayout; const ALookup: TClassAncestorsLookup; out ANewAncestors: TArray<string>;
  const AInterfaceName: string): string;
var
  First: string;
begin
  Result := '';
  ANewAncestors := Copy(ALayout.Ancestors);
  if (Length(ANewAncestors) = 0) or SameText(ANewAncestors[0], 'TObject') or
    SameText(ANewAncestors[0], 'System.TObject') then
  begin
    if Length(ANewAncestors) > 1 then
    begin
      // TObject mit Interfaces: Die Klasse implementiert IInterface schon selbst.
      ANewAncestors := ANewAncestors + [AInterfaceName];
    end
    else
    begin
      ANewAncestors := ['TInterfacedObject', AInterfaceName];
    end;
    Exit;
  end;
  if Length(ANewAncestors) = 1 then
  begin
    First := ANewAncestors[0];
    case TExtractInterface.Supports(First, ALookup) of
      TInterfaceSupport.No:
        Result := cTexts[TEditingExtractInterfaceText.DoesNotImplementIInterfaceLacks].Fmt([First, ALayout.Name]);
      TInterfaceSupport.Unknown:
        Result := cTexts[TEditingExtractInterfaceText.WhetherImplementsIInterfaceIsNot].Fmt([First, ALayout.Name]);
    end;
  end;
  ANewAncestors := ANewAncestors + [AInterfaceName];
end;

function HasEnabled(const AItems: TArray<TExtractCandidate>): Boolean;
var
  mItem: TExtractCandidate;
begin
  Result := False;
  for mItem in AItems do
  begin
    Result := Result or mItem.Enabled;
  end;
end;

class function TExtractInterface.Prepare(const ASource: TClassSource; const ALookups: TExtractInterfaceLookups;
  out AInfo: TExtractInterfaceInfo; out AReason: string): Boolean;
var
  mDecl: TSyntaxNode;
  mLayout: TClassLayout;
  mAncestors: TArray<string>;
  mNote: string;
begin
  AInfo := Default(TExtractInterfaceInfo);
  AReason := '';
  mDecl := ClassAt(ASource.Tree, ASource.Line);
  if mDecl = nil then
  begin
    AReason := cTexts[TEditingExtractInterfaceText.ThereIsNoClassAt].Text;
    Exit(False);
  end;
  mLayout := TClassLayout.Read(ASource.Tree, ASource.Text, mDecl);
  try
    AInfo.ClassName := mLayout.Name;
    AInfo.SuggestedName := DefaultName(mLayout.Name);
    AInfo.Candidates := Candidates(mLayout, ALookups.IsMethodPointer);
    mNote := AncestorNote(mLayout, ALookups.Ancestors, mAncestors, AInfo.SuggestedName);
    if mNote <> '' then
    begin
      AInfo.Notes := AInfo.Notes + [mNote];
    end;
  finally
    mLayout.Free;
  end;
  Result := HasEnabled(AInfo.Candidates);
  if not Result then
  begin
    AReason := cTexts[TEditingExtractInterfaceText.HasNoPublicOrPublished].Fmt([AInfo.ClassName]);
  end;
end;

/// <summary>Erste Bezeichner aller Typverweise unter ANode.</summary>
procedure CollectTypeNames(ANode: TSyntaxNode; var ANames: TArray<string>);
var
  Found: TArray<string>;
  Name: string;
begin
  // Var-Parameter lassen sich nicht einfangen: erst sammeln, dann anhängen.
  Found := nil;
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    var
      Part: string;
    begin
      Result := True;
      if AChild.Kind <> TSyntaxKind.TypeReference then
      begin
        Exit;
      end;
      Part := AChild.Name;
      if Pos('.', Part) > 0 then
      begin
        Part := Copy(Part, 1, Pos('.', Part) - 1);
      end;
      if (Part <> '') and IsIdentifier(Part) then
      begin
        Found := Found + [Part];
      end;
    end);
  for Name in Found do
  begin
    if IndexText(Name, ANames) < 0 then
    begin
      ANames := ANames + [Name];
    end;
  end;
end;

function MethodDeclaration(ALayout: TClassLayout; AIndex: Integer): string;
var
  Directive: string;
begin
  Result := ALayout.Head(AIndex);
  for Directive in ALayout.Members[AIndex].Directives do
  begin
    if MatchText(Directive, KeptDirectives) then
    begin
      Result := Result + ' ' + Directive + ';';
    end;
  end;
end;

function PropertyDeclaration(const AMember: TClassMember; const AReader, AWriter: string): string;
begin
  Result := 'property ' + AMember.Name;
  if AMember.Parameters <> '' then
  begin
    Result := Result + '[' + AMember.Parameters + ']';
  end;
  Result := Result + ': ' + AMember.TypeName;
  if AMember.IndexSpecifier <> '' then
  begin
    Result := Result + ' index ' + AMember.IndexSpecifier;
  end;
  if AReader <> '' then
  begin
    Result := Result + ' read ' + AReader;
  end;
  if AWriter <> '' then
  begin
    Result := Result + ' write ' + AWriter;
  end;
  Result := Result + ';';
  if AMember.IsDefaultArray then
  begin
    Result := Result + ' default;';
  end;
end;

/// <summary>Ist AName eine Methode der Klasse (Zugriffsmethode statt Feld)?</summary>
function MethodIndex(ALayout: TClassLayout; const AName: string): Integer;
var
  Index: Integer;
begin
  for Index in ALayout.Find(AName) do
  begin
    if ALayout.Members[Index].IsMethod then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

function UniqueMemberName(ALayout: TClassLayout; const ABase: string; const ATaken: TArray<string>): string;
var
  Counter: Integer;
begin
  Result := ABase;
  Counter := 1;
  while (ALayout.Find(Result) <> nil) or (IndexText(Result, ATaken) >= 0) do
  begin
    Inc(Counter);
    Result := ABase + IntToStr(Counter);
  end;
end;

/// <summary>Ist AName schon vergeben (die Klasse selbst, eine Klasse der Unit, laut Rückfrage)?</summary>
function NameTaken(ATree: TSyntaxTree; ALayout: TClassLayout; const AName: string;
  const ANameInUse: TNameInUse): Boolean;
begin
  Result := SameText(AName, ALayout.Name) or (TClassLayout.DeclNamed(ATree, AName) <> nil) or
    (Assigned(ANameInUse) and ANameInUse(AName));
end;

/// <summary>Grund, warum der Kandidat AId nicht gewählt werden kann; '' wenn er kann.</summary>
function CandidateError(const AItems: TArray<TExtractCandidate>; AId: Integer): string;
var
  mItem: TExtractCandidate;
begin
  Result := cTexts[TEditingExtractInterfaceText.TheClassHasChangedPlease].Text;
  for mItem in AItems do
  begin
    if (mItem.Id = AId) and not mItem.Enabled then
    begin
      Exit(cTexts[TEditingExtractInterfaceText.CannotGoIntoTheInterface].Fmt([mItem.Name, mItem.Reason]));
    end;
    if mItem.Id = AId then
    begin
      Result := '';
    end;
  end;
end;

/// <summary>Grund, warum ARequest an der Klasse ADecl nicht geht (keine Klasse, Name, leere Auswahl); '' sonst.
/// </summary>
function RequestError(ADecl: TSyntaxNode; const ARequest: TExtractInterfaceRequest): string;
begin
  Result := '';
  if ADecl = nil then
  begin
    Result := cTexts[TEditingExtractInterfaceText.ThereIsNoClassAt].Text;
  end
  else if not IsIdentifier(ARequest.Name) then
  begin
    Result := cTexts[TEditingExtractInterfaceText.IsNotAValidIdentifier].Fmt([ARequest.Name]);
  end
  else if ARequest.Members = nil then
  begin
    Result := cTexts[TEditingExtractInterfaceText.NoMemberIsSelected].Text;
  end;
end;

/// <summary>Grund, warum Name oder Auswahl an ALayout nicht gehen; '' sonst. AChosen: die gewählten Ids.</summary>
function ChoiceError(ATree: TSyntaxTree; ALayout: TClassLayout; const ARequest: TExtractInterfaceRequest;
  const ALookups: TExtractInterfaceLookups; out AChosen: TArray<Integer>): string;
var
  mItems: TArray<TExtractCandidate>;
  mId: Integer;
begin
  AChosen := nil;
  if NameTaken(ATree, ALayout, ARequest.Name, ALookups.NameInUse) then
  begin
    Exit(cTexts[TEditingExtractInterfaceText.TheNameIsAlreadyTaken].Fmt([ARequest.Name]));
  end;
  mItems := Candidates(ALayout, ALookups.IsMethodPointer);
  Result := '';
  for mId in ARequest.Members do
  begin
    Result := CandidateError(mItems, mId);
    if Result <> '' then
    begin
      Exit;
    end;
    AChosen := AChosen + [mId];
  end;
end;

type
  /// <summary>Baut Interface und Änderungen an der Klasse für TExtractInterface.Plan.</summary>
  TInterfaceBuilder = class
  strict private
    FLayout: TClassLayout;
    FRequest: TExtractInterfaceRequest;
    FPlan: TExtractInterfacePlan;
    FMethods: TArray<Integer>;
    FPropertyLines: TArray<string>;
    FNewMethods: TArray<string>;
    FNewBodies: TArray<string>;
    FTaken: TArray<string>;
    FPropertyEdits: TArray<TTextEdit>;
    procedure AddMethod(AIndex: Integer);
    /// <summary>Nimmt die Zugriffsmethode AAccessor mit; ist sie nicht öffentlich, mit Warnung.</summary>
    procedure TakeAccessor(AAccessor: Integer; const AName, AProperty: string);
    procedure Redirect(AId: Integer; const AKind, AName: string);
    function NewName(const ABase: string): string;
    /// <summary>Lesezugriff der Property im Interface: vorhandene Methode oder neuer Getter für ein Feld.</summary>
    function ReadAccessor(AId: Integer): string;
    /// <summary>Schreibzugriff der Property im Interface: vorhandene Methode oder neuer Setter für ein Feld.
    /// </summary>
    function WriteAccessor(AId: Integer): string;
    procedure AddProperty(AId: Integer);
    function MemberLines(const AChosen: TArray<Integer>): string;
    function SameUnitEdit: TTextEdit;
  public
    constructor Create(ALayout: TClassLayout; const ARequest: TExtractInterfaceRequest; AClassOffset: Integer);
    procedure Collect(const AChosen: TArray<Integer>);
    /// <summary>Vorfahrenliste, neue Zugriffsmethoden mit Rümpfen, umgestellte Properties und mit SameUnit das
    /// Interface selbst; False mit Grund ohne implementation-Teil für neue Rümpfe.</summary>
    function ClassEdits(ATree: TSyntaxTree; const AText: string; const ALookup: TClassAncestorsLookup;
      out AReason: string): Boolean;
    property Plan: TExtractInterfacePlan read FPlan;
  end;

constructor TInterfaceBuilder.Create(ALayout: TClassLayout; const ARequest: TExtractInterfaceRequest;
  AClassOffset: Integer);
begin
  inherited Create;
  FLayout := ALayout;
  FRequest := ARequest;
  FPlan.ClassName := ALayout.Name;
  FPlan.InterfaceName := ARequest.Name;
  FPlan.InInterface := ALayout.InInterface;
  FPlan.ClassOffset := AClassOffset;
end;

procedure TInterfaceBuilder.AddMethod(AIndex: Integer);
var
  mKnown: Integer;
begin
  for mKnown in FMethods do
  begin
    if mKnown = AIndex then
    begin
      Exit;
    end;
  end;
  FMethods := FMethods + [AIndex];
end;

procedure TInterfaceBuilder.TakeAccessor(AAccessor: Integer; const AName, AProperty: string);
begin
  AddMethod(AAccessor);
  if FLayout.Members[AAccessor].Visibility in [TClassVisibility.StrictPrivate, TClassVisibility.Private_,
    TClassVisibility.StrictProtected, TClassVisibility.Protected_] then
  begin
    FPlan.Warnings := FPlan.Warnings + [cTexts[TEditingExtractInterfaceText.GoesIntoTheInterfaceToo].Fmt([AName,
      AProperty])];
  end;
end;

procedure TInterfaceBuilder.Redirect(AId: Integer; const AKind, AName: string);
var
  mEdit: TTextEdit;
begin
  // Property in der Klasse auf die neue Methode umstellen.
  if TClassEdits.ReplaceAccessor(FLayout, AId, AKind, AName, mEdit) then
  begin
    FPropertyEdits := FPropertyEdits + [mEdit];
  end;
end;

function TInterfaceBuilder.NewName(const ABase: string): string;
begin
  Result := UniqueMemberName(FLayout, ABase, FTaken);
  FTaken := FTaken + [Result];
end;

function TInterfaceBuilder.ReadAccessor(AId: Integer): string;
var
  mMember: TClassMember;
  mAccessor: Integer;
  mGetter, mLineBreak: string;
begin
  mMember := FLayout.Members[AId];
  Result := mMember.ReadAccessor;
  mAccessor := -1;
  if Result <> '' then
  begin
    mAccessor := MethodIndex(FLayout, Result);
  end;
  if mAccessor >= 0 then
  begin
    TakeAccessor(mAccessor, Result, mMember.Name);
  end
  else if Result <> '' then
  begin
    // Feld: Getter anlegen.
    mLineBreak := FLayout.LineBreak;
    mGetter := NewName('Get' + mMember.Name);
    FNewMethods := FNewMethods + [Format('function %s: %s;', [mGetter, mMember.TypeName])];
    FNewBodies := FNewBodies + [Format('function %s.%s: %s;', [FLayout.Name, mGetter, mMember.TypeName]) +
      mLineBreak + 'begin' + mLineBreak + '  Result := ' + Result + ';' + mLineBreak + 'end;'];
    Redirect(AId, 'read', mGetter);
    Result := mGetter;
  end;
end;

function TInterfaceBuilder.WriteAccessor(AId: Integer): string;
const
  cValue = 'Value';
var
  mMember: TClassMember;
  mAccessor: Integer;
  mSetter, mLineBreak: string;
begin
  mMember := FLayout.Members[AId];
  Result := mMember.WriteAccessor;
  mAccessor := -1;
  if Result <> '' then
  begin
    mAccessor := MethodIndex(FLayout, Result);
  end;
  if mAccessor >= 0 then
  begin
    TakeAccessor(mAccessor, Result, mMember.Name);
  end
  else if Result <> '' then
  begin
    // Feld: Setter anlegen.
    mLineBreak := FLayout.LineBreak;
    mSetter := NewName('Set' + mMember.Name);
    FNewMethods := FNewMethods + [Format('procedure %s(const %s: %s);', [mSetter, cValue, mMember.TypeName])];
    FNewBodies := FNewBodies + [Format('procedure %s.%s(const %s: %s);', [FLayout.Name, mSetter, cValue,
      mMember.TypeName]) + mLineBreak + 'begin' + mLineBreak + '  ' + Result + ' := ' + cValue + ';' +
      mLineBreak + 'end;'];
    Redirect(AId, 'write', mSetter);
    Result := mSetter;
  end;
end;

procedure TInterfaceBuilder.AddProperty(AId: Integer);
var
  mReader, mWriter, mDoc: string;
begin
  mReader := ReadAccessor(AId);
  mWriter := WriteAccessor(AId);
  for mDoc in FLayout.DocLines(AId) do
  begin
    FPropertyLines := FPropertyLines + ['  ' + mDoc];
  end;
  FPropertyLines := FPropertyLines + ['  ' + PropertyDeclaration(FLayout.Members[AId], mReader, mWriter)];
end;

function TInterfaceBuilder.MemberLines(const AChosen: TArray<Integer>): string;
var
  mIndex: Integer;
  mText: string;
begin
  Result := '';
  // Methoden vor die Properties.
  for mIndex in FMethods do
  begin
    for mText in FLayout.DocLines(mIndex) do
    begin
      Result := Result + #10'  ' + mText;
    end;
    Result := Result + #10'  ' + MethodDeclaration(FLayout, mIndex);
    FPlan.Methods := FPlan.Methods + [FLayout.Members[mIndex].Name];
    CollectTypeNames(FLayout.Members[mIndex].Node, FPlan.TypeNames);
  end;
  for mText in FNewMethods do
  begin
    Result := Result + #10'  ' + mText;
  end;
  for mText in FPropertyLines do
  begin
    Result := Result + #10 + mText;
  end;
  for mIndex in AChosen do
  begin
    if FLayout.Members[mIndex].Kind = TClassMemberKind.Property_ then
    begin
      CollectTypeNames(FLayout.Members[mIndex].Node, FPlan.TypeNames);
    end;
  end;
end;

procedure TInterfaceBuilder.Collect(const AChosen: TArray<Integer>);
var
  mId: Integer;
begin
  // Methoden in Reihenfolge der Klasse, dann die Zugriffsmethoden der Properties.
  for mId in AChosen do
  begin
    if FLayout.Members[mId].Kind <> TClassMemberKind.Property_ then
    begin
      AddMethod(mId);
    end;
  end;
  for mId in AChosen do
  begin
    if FLayout.Members[mId].Kind = TClassMemberKind.Property_ then
    begin
      AddProperty(mId);
    end;
  end;
  FPlan.Declaration := FRequest.Name + ' = interface' + #10'  [''' + FRequest.Guid + ''']' + MemberLines(AChosen) +
    #10'end;';
end;

function TInterfaceBuilder.SameUnitEdit: TTextEdit;
var
  mText, mLine: string;
begin
  mText := '';
  for mLine in FPlan.Declaration.Split([#10]) do
  begin
    mText := mText + FLayout.Indent + mLine + FLayout.LineBreak;
  end;
  Result := TClassEdits.InsertBeforeLine(FLayout.FirstLine, mText + FLayout.LineBreak);
end;

function TInterfaceBuilder.ClassEdits(ATree: TSyntaxTree; const AText: string; const ALookup: TClassAncestorsLookup;
  out AReason: string): Boolean;
var
  mAncestors: TArray<string>;
  mNote: string;
  mBodiesLine: Integer;
begin
  AReason := '';
  mNote := AncestorNote(FLayout, ALookup, mAncestors, FRequest.Name);
  if mNote <> '' then
  begin
    FPlan.Warnings := TArray<string>.Create(mNote) + FPlan.Warnings;
  end;
  FPlan.Edits := TArray<TTextEdit>.Create(TClassEdits.SetAncestors(FLayout, mAncestors)) + FPropertyEdits;
  if FNewMethods <> nil then
  begin
    FPlan.Edits := FPlan.Edits + [TClassEdits.InsertMembers(FLayout, TClassVisibility.Private_, False, FNewMethods)];
    mBodiesLine := TClassEdits.BodiesEnd(ATree, FLayout.Name);
    if mBodiesLine < 0 then
    begin
      AReason := cTexts[TEditingExtractInterfaceText.TheUnitHasNoImplementation].Text;
      Exit(False);
    end;
    FPlan.Edits := FPlan.Edits + [TClassEdits.InsertBodies(AText, mBodiesLine, FNewBodies)];
  end;
  if FRequest.SameUnit then
  begin
    FPlan.Edits := FPlan.Edits + [SameUnitEdit];
  end;
  Result := True;
end;

class function TExtractInterface.Plan(const ASource: TClassSource; const ARequest: TExtractInterfaceRequest;
  const ALookups: TExtractInterfaceLookups; out APlan: TExtractInterfacePlan; out AReason: string): Boolean;
var
  mDecl: TSyntaxNode;
  mLayout: TClassLayout;
  mBuilder: TInterfaceBuilder;
  mChosen: TArray<Integer>;
begin
  APlan := Default(TExtractInterfacePlan);
  mDecl := ClassAt(ASource.Tree, ASource.Line);
  AReason := RequestError(mDecl, ARequest);
  if AReason <> '' then
  begin
    Exit(False);
  end;
  mLayout := TClassLayout.Read(ASource.Tree, ASource.Text, mDecl);
  try
    AReason := ChoiceError(ASource.Tree, mLayout, ARequest, ALookups, mChosen);
    Result := AReason = '';
    if Result then
    begin
      mBuilder := TInterfaceBuilder.Create(mLayout, ARequest, mDecl.StartOffset);
      try
        mBuilder.Collect(mChosen);
        Result := mBuilder.ClassEdits(ASource.Tree, ASource.Text, ALookups.Ancestors, AReason);
        APlan := mBuilder.Plan;
      finally
        mBuilder.Free;
      end;
    end;
  finally
    mLayout.Free;
  end;
end;

class function TExtractInterface.InsertIntoUnit(ATree: TSyntaxTree; const AText, ADeclaration: string;
  out AEdit: TTextEdit): Boolean;
var
  Implementation_, Interface_: TSyntaxNode;
  Index, Line: Integer;
  LineBreak, Text, Part: string;
begin
  Implementation_ := nil;
  Interface_ := nil;
  for Index := 0 to ATree.Root.ChildCount - 1 do
  begin
    if ATree.Root[Index].Kind = TSyntaxKind.ImplementationSection then
    begin
      Implementation_ := ATree.Root[Index];
    end
    else if ATree.Root[Index].Kind = TSyntaxKind.InterfaceSection then
    begin
      Interface_ := ATree.Root[Index];
    end;
  end;
  if (Interface_ = nil) or (Implementation_ = nil) then
  begin
    Exit(False);
  end;
  LineBreak := TTextLines.LineBreakOf(AText);
  Text := 'type' + LineBreak;
  for Part in ADeclaration.Split([#10]) do
  begin
    Text := Text + '  ' + Part + LineBreak;
  end;
  Line := Implementation_.StartPos.Line;
  AEdit := TClassEdits.InsertBeforeLine(Line, Text + LineBreak);
  Result := True;
end;

class function TExtractInterface.NewUnitText(const AUnitName, ADeclaration: string; const AUses: TArray<string>;
  const ALineBreak: string): string;
var
  Part: string;
begin
  Result := 'unit ' + AUnitName + ';' + ALineBreak + ALineBreak + 'interface' + ALineBreak + ALineBreak;
  if AUses <> nil then
  begin
    Result := Result + 'uses' + ALineBreak + '  ' + string.Join(',' + ALineBreak + '  ', AUses) + ';' + ALineBreak +
      ALineBreak;
  end;
  Result := Result + 'type' + ALineBreak;
  for Part in ADeclaration.Split([#10]) do
  begin
    Result := Result + '  ' + Part + ALineBreak;
  end;
  Result := Result + ALineBreak + 'implementation' + ALineBreak + ALineBreak + 'end.' + ALineBreak;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.ExtractInterface', cTexts);

end.
