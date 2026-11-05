unit Atlas.Common.Rules.Builtin.Unused;

// Ungenutzte Variablen und Parameter ohne Compilerlauf (#91):
//   unused-local        lokale Variable wird nirgends verwendet (wie H2164)
//   unused-parameter    Parameter wird im Rumpf nicht verwendet
//   unused-assignment   zugewiesener Wert wird nie gelesen (wie H2077)
//   duplicate-assignment  Feld oder Property zweimal hintereinander gesetzt (#1051)
//
// Verwendung ist jedes Vorkommen des Namens in der Routine, auch in lokalen
// Routinen und anonymen Methoden, sowie "absolute Name" im var-Abschnitt.
// Enthält die Routine bedingte Kompilierung ({$IF…}), sieht der Syntaxbaum
// inaktive Zweige nicht: Kommt der Name dann im Text vor, gibt es keinen
// Treffer, sonst nur einen mit niedriger Konfidenz; unused-assignment
// schweigt in solchen Routinen ganz. Routinen mit asm-Rumpf werden übergangen.
// unused-assignment übergeht Variablen mit Interface-Typ (Referenzzähler: Bereichswächter, X := nil).
// Ebenso still bleibt das Leeren eines zuvor gesetzten Werts (X := nil, '', Default(T), T.Empty): Es gibt
// Speicher und Referenzen vorzeitig frei oder schützt nach Free. Leeren ohne vorherigen Wert meldet sie weiter.
// Den Code H2077 nennt die Meldung nur bei bekanntem, nicht verwaltetem Typ: Für Strings, dynamische
// Arrays, Variants und Records mit solchen Feldern meldet dcc nichts (#1383, Cm.E2056).
//
// unused-parameter nimmt aus:
// - Parameter namens Sender und Routinen mit einem solchen (Ereignis-Handler),
// - Methoden mit override, virtual, dynamic, abstract oder message,
//   published-Methoden (DFM-Ereignisse), Methoden von Klassen mit Interfaces
//   und Methoden, deren Typdeklaration nicht in der Datei steht,
// - Routinen, die als Wert verwendet werden (@P, X := P, X := Obj.P, Aufruf(P)), auch in Tabellen:
//   typisierte Konstante (array[…] of TFix = (A, B), Record-Konstante (Lauf: A)), Array-Literal [A, B] und
//   Vorbelegung (X: TFix = A) (#1451).
// Nicht ausgenommen ist eine Routine, die nur aus einer anonymen Methode oder einem Override aufgerufen wird:
// Vorgegeben ist dann deren Signatur, die eigene ist frei. Nicht sichtbar ist die Übergabe als Wert in einer
// anderen Unit (Obj.OnX := TFoo.Handler dort, Handler ohne Sender, nicht published): Der Index kennt keine
// Verwendungen. Dort hilft nur // lsp-ignore: unused-parameter mit Grund.
//
// Option aller drei Regeln: {"ignore": ["Dummy*", "_*"]} nimmt Namen nach
// Muster aus (* und ? als Platzhalter).
//
// duplicate-assignment vergleicht Zuweisungen derselben Anweisungsfolge an
// Felder, Properties und Mitglieder (Panel.Left, Self.FWert, P^.X, Feld der
// eigenen Klasse ohne Self); lokale Variablen deckt unused-assignment ab.
// Dazwischen dürfen nur Zuweisungen an andere Objekte stehen, deren Werte
// nichts aufrufen und das Ziel nicht nennen; der zweite Wert darf das Ziel
// nicht lesen und nichts aufrufen. Ziele mit Index oder Aufruf zählen nicht.
// Still bleibt der Wechsel False/True (stößt bei Active, Open … etwas an),
// eine zweite Zuweisung, die nur unter einer weiteren Bedingung übersetzt
// wird ({$IFDEF DEBUG} Caption := …), und Properties aus allowProperties
// (Muster, Standard Visible, Enabled). Fehlt das Gegenstück (Left/Top,
// Width/Height …) in der Folge, nennt die Meldung es als Vermutung.
//
// empty-routine (#977): Rumpf ohne Anweisung und ohne Kommentar (auch keine
// Direktive). Ausgenommen sind virtuelle bzw. dynamische Methoden (Ersatz für
// abstract), Nachrichten-Handler und Ereignis-Handler aus der Formulardatei.
// Korrekturen: Kommentar zwischen begin und end; "Methode entfernen" nur für
// private Methoden bzw. Routinen ohne Deklaration im interface, die in der
// Datei nirgends vorkommen und keine Signatur von außen erfüllen.
//
// duplicate-assignment steht in Unused.Duplicates, empty-routine in Unused.EmptyRoutines, gemeinsame Hilfen
// (MatchesWildcard, Namen, Bereiche, vorgegebene Signaturen) in Unused.Shared; angemeldet werden alle hier.

interface

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TUnusedLocalRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TUnusedParameterRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TUnusedAssignmentRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterUnusedRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.ManagedTypes,
  Atlas.Common.Rules.Builtin.Flow,
  Atlas.Common.Rules.Builtin.Unused.Shared,
  Atlas.Common.Rules.Builtin.Unused.Duplicates,
  Atlas.Common.Rules.Builtin.Unused.EmptyRoutines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TUnusedText = (LocalTitle, RemoveVariable, LocalUnused, ParamTitle, ParamUnused, AssignedTitle, LikeH2077,
    NeverRead);

const
  cTexts: array[TUnusedText] of TAtlasText = (
    (De: 'Lokale Variable wird nicht verwendet'; En: 'Local variable is not used'),
    (De: 'Variable "%s" entfernen'; En: 'Remove variable "%s"'),
    (De: 'Variable "%s" wird nicht verwendet'; En: 'Variable "%s" is not used'),
    (De: 'Parameter wird nicht verwendet'; En: 'Parameter is not used'),
    (De: 'Parameter "%s" wird nicht verwendet'; En: 'Parameter "%s" is not used'),
    (De: 'Zugewiesener Wert wird nie gelesen'; En: 'Assigned value is never read'),
    (De: ' (wie H2077)'; En: ' (like H2077)'),
    (De: 'Der an "%s" zugewiesene Wert wird nie gelesen%s'; En: 'The value assigned to "%s" is never read%s'));

{$SCOPEDENUMS OFF}

type
  TNameSet = TDictionary<string, Boolean>;
  TSyntaxKinds = set of TSyntaxKind;

  /// <summary>Was die Prüfung einer Routine braucht.</summary>
  TRoutineInfo = record
    Routine: TSyntaxNode;
    Block: TSyntaxNode;
    Conditionals: Boolean;
  end;

function ContainsKind(ANode: TSyntaxNode; AKind: TSyntaxKind): Boolean;
var
  Kind: TSyntaxKind;
begin
  Kind := AKind;
  // Iterativ (Bericht M1).
  Result := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      if AVisited.Kind = Kind then
      begin
        Exit(TSyntaxSearchStep.Found);
      end;
      Result := TSyntaxSearchStep.Descend;
    end) <> nil;
end;

/// <summary>Namen, die in ANode verwendet werden (klein geschrieben): Bezeichner und Schleifenvariablen.</summary>
procedure CollectUses(ANode: TSyntaxNode; ASet: TNameSet);
var
  Names: TNameSet;
begin
  Names := ASet;
  // Iterativ (Bericht M1): Der Lauf geht auch durch lange Ausdrucksketten.
  ANode.Walk(
    function(AVisited: TSyntaxNode): Boolean
    begin
      if AVisited.Kind in [TSyntaxKind.Identifier, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement] then
      begin
        Names.AddOrSetValue(LowerCase(AVisited.Name), True);
      end;
      Result := True;
    end);
end;

/// <summary>Enthält die Routine Direktiven der bedingten Kompilierung?</summary>
function HasConditionals(const AContext: TRuleContext; ARoutine: TSyntaxNode): Boolean;
var
  mIndex: Integer;
  Text: string;
begin
  // Ab der Routine statt ab Dateianfang und ohne Kopie je Token (#1323).
  for mIndex := AContext.Tree.FirstTokenFrom(ARoutine.StartOffset) to High(AContext.Tree.Tokens) do
  begin
    if AContext.Tree.Tokens[mIndex].Offset >= ARoutine.EndOffset then
    begin
      Break;
    end;
    if AContext.Tree.Tokens[mIndex].Kind <> TPascalTokenKind.Directive then
    begin
      Continue;
    end;
    Text := UpperCase(AContext.Tree.Tokens[mIndex].Text);
    if StartsStr('{$IF', Text) or StartsStr('(*$IF', Text) or StartsStr('{$ELSE', Text) or
      StartsStr('(*$ELSE', Text) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Kommt AName als ganzes Wort im Text zwischen den Offsets vor (Kommentare eingeschlossen)?</summary>
function OccursInText(const AText, AName: string; AStart, AEnd: Integer): Boolean;
var
  Text, Name: string;
  Position: Integer;

  function IsWordChar(AIndex: Integer): Boolean;
  begin
    Result := (AIndex >= 1) and (AIndex <= Length(Text)) and
      (CharInSet(Text[AIndex], ['a'..'z', '0'..'9', '_']) or (Ord(Text[AIndex]) > 127));
  end;

begin
  Text := LowerCase(Copy(AText, 1, AEnd));
  Name := LowerCase(AName);
  Position := PosEx(Name, Text, AStart + 1);
  while Position > 0 do
  begin
    if not IsWordChar(Position - 1) and not IsWordChar(Position + Length(Name)) then
    begin
      Exit(True);
    end;
    Position := PosEx(Name, Text, Position + 1);
  end;
  Result := False;
end;

/// <summary>"absolute AName" in einem var-Abschnitt der Routine.</summary>
function UsedByAbsolute(const AContext: TRuleContext; ARoutine: TSyntaxNode; const AName: string): Boolean;
var
  Index, Position: Integer;
  Section: TSyntaxNode;
  Text: string;
begin
  for Index := 0 to ARoutine.ChildCount - 1 do
  begin
    Section := ARoutine[Index];
    if Section.Kind <> TSyntaxKind.VarSection then
    begin
      Continue;
    end;
    Text := LowerCase(Copy(AContext.Text, Section.StartOffset + 1, Section.EndOffset - Section.StartOffset));
    Position := Pos('absolute', Text);
    while Position > 0 do
    begin
      if StartsStr(LowerCase(AName), TrimLeft(Copy(Text, Position + 8, MaxInt))) then
      begin
        Exit(True);
      end;
      Position := PosEx('absolute', Text, Position + 8);
    end;
  end;
  Result := False;
end;

/// <summary>Ist AName ungenutzt? AConfidence ist dann gesetzt.</summary>
function IsUnused(const AContext: TRuleContext; const AInfo: TRoutineInfo; AUses: TNameSet;
  const AName: string; AAfterOffset: Integer; out AConfidence: TRuleConfidence): Boolean;
begin
  Result := False;
  AConfidence := TRuleConfidence.High;
  if AUses.ContainsKey(LowerCase(AName)) or UsedByAbsolute(AContext, AInfo.Routine, AName) then
  begin
    Exit;
  end;
  if AInfo.Conditionals then
  begin
    // Vielleicht in einem inaktiven Zweig verwendet.
    if OccursInText(AContext.Text, AName, AAfterOffset, AInfo.Routine.EndOffset) then
    begin
      Exit;
    end;
    AConfidence := TRuleConfidence.Low;
  end;
  Result := True;
end;

function RoutineInfo(const AContext: TRuleContext; ARoutine: TSyntaxNode; out AInfo: TRoutineInfo): Boolean;
begin
  AInfo.Routine := ARoutine;
  AInfo.Block := ARoutine.FindChild(TSyntaxKind.Block);
  AInfo.Conditionals := False;
  Result := (AInfo.Block <> nil) and not ContainsKind(ARoutine, TSyntaxKind.AsmBlock);
  if Result then
  begin
    AInfo.Conditionals := HasConditionals(AContext, ARoutine);
  end;
end;

/// <summary>Var-Deklarationen der var-Abschnitte von ARoutine.</summary>
function VarDecls(ARoutine: TSyntaxNode): TArray<TSyntaxNode>;
var
  mIndex, mInner: Integer;
  mSection: TSyntaxNode;
begin
  Result := nil;
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    mSection := ARoutine[mIndex];
    if mSection.Kind <> TSyntaxKind.VarSection then
    begin
      Continue;
    end;
    for mInner := 0 to mSection.ChildCount - 1 do
    begin
      if mSection[mInner].Kind = TSyntaxKind.VarDecl then
      begin
        Result := Result + [mSection[mInner]];
      end;
    end;
  end;
end;

type
  /// <summary>Gemeinsamer Lauf von unused-local und unused-parameter über die Routinen einer Datei.</summary>
  TUnusedNamesCheck = class
  protected
    FContext: TRuleContext;
    FReport: IRuleReport;
    FCache: IRuleDerivedCache;
    FPatterns: TArray<string>;
    FUses: TNameSet;
    FInfo: TRoutineInfo;
    /// <summary>Verwendungen aus den Kindern von ARoutine der Arten AKinds.</summary>
    procedure CollectRoutineUses(ARoutine: TSyntaxNode; const AKinds: TSyntaxKinds);
    procedure CheckRoutine(ARoutine: TSyntaxNode); virtual; abstract;
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

  TUnusedLocalCheck = class(TUnusedNamesCheck)
  private
    procedure CheckDecl(ASection, ADecl: TSyntaxNode);
  protected
    procedure CheckRoutine(ARoutine: TSyntaxNode); override;
  end;

  TUnusedParameterCheck = class(TUnusedNamesCheck)
  private
    /// <summary>Namen, die irgendwo in der Datei als Wert verwendet werden (klein); einmal je Datei gesammelt,
    /// nil bis zum ersten Bedarf. Vorher durchsuchte jede Routine den ganzen Baum: quadratisch in der Länge
    /// der Unit (26.000 Zeilen: 52 s für die ganze Prüfung).</summary>
    FValueNames: TNameSet;
    procedure CheckParameter(AHeader, AParam: TSyntaxNode);
    function UsedAsValue(const AName: string): Boolean;
    function SignatureGiven(ARoutine: TSyntaxNode): Boolean;
  protected
    procedure CheckRoutine(ARoutine: TSyntaxNode); override;
  public
    destructor Destroy; override;
  end;

{ TUnusedNamesCheck }

constructor TUnusedNamesCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FPatterns := IgnorePatterns(AContext.Options);
  FCache := TRuleDerived.Open(AContext);
  FUses := TNameSet.Create;
end;

destructor TUnusedNamesCheck.Destroy;
begin
  FUses.Free;
  inherited Destroy;
end;

procedure TUnusedNamesCheck.CollectRoutineUses(ARoutine: TSyntaxNode; const AKinds: TSyntaxKinds);
var
  mIndex: Integer;
begin
  FUses.Clear;
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    if ARoutine[mIndex].Kind in AKinds then
    begin
      CollectUses(ARoutine[mIndex], FUses);
    end;
  end;
end;

procedure TUnusedNamesCheck.Run;
var
  mRoutine: TSyntaxNode;
begin
  for mRoutine in TRuleDerived.Routines(FCache, FContext) do
  begin
    if RoutineInfo(FContext, mRoutine, FInfo) then
    begin
      CheckRoutine(mRoutine);
    end;
  end;
end;

{ TUnusedLocalRule }

function TUnusedLocalRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('unused-local', TRuleSeverity.Hint, cTexts[TUnusedText.LocalTitle].Text);
end;

/// <summary>Ende der Inline-Variablen ab AOffset samt Leerzeichen und ";" dahinter.</summary>
function InlineVarEnd(const AText: string; AOffset: Integer): Integer;
begin
  Result := AOffset;
  while (Result < Length(AText)) and (AText[Result + 1] = ' ') do
  begin
    Inc(Result);
  end;
  if (Result < Length(AText)) and (AText[Result + 1] = ';') then
  begin
    Inc(Result);
  end;
end;

/// <summary>Entfernt die Inline-Variable ADecl samt Zeile; nur ohne oder mit einfachem Startwert, ein Aufruf
/// hätte Nebenwirkungen.</summary>
function InlineVarFix(const ACache: IRuleDerivedCache; const AContext: TRuleContext; ADecl: TSyntaxNode;
  const ATitle: string; out AFix: TRuleFix): Boolean;
var
  mLineStart, mLineEnd: Integer;
begin
  Result := (ADecl.ChildCount = 0) or ((ADecl.ChildCount = 1) and (ADecl[0].Kind = TSyntaxKind.Literal));
  Result := Result and WholeLines(AContext.Text, ADecl.StartOffset, InlineVarEnd(AContext.Text, ADecl.EndOffset),
    mLineStart, mLineEnd);
  if Result then
  begin
    AFix := TRuleFix.Create(ATitle, [TRuleEdit.Create(TRuleDerived.OffsetRange(ACache, AContext, mLineStart,
      mLineEnd), '')]);
  end;
end;

/// <summary>Bereich, der AName aus der Liste ANames in ADecl samt Komma entfernt; False ohne sicheren Bereich.
/// </summary>
function ListNameSpan(const AContext: TRuleContext; ADecl: TSyntaxNode; const ANames: TArray<string>;
  const AName: string; out AStart, AStop: Integer): Boolean;
var
  mPosition, mIndex: Integer;
  mToken, mNeighbour: TPascalToken;
begin
  AStart := 0;
  AStop := 0;
  mPosition := -1;
  for mIndex := 0 to High(ANames) do
  begin
    if SameText(ANames[mIndex], AName) then
    begin
      mPosition := mIndex;
    end;
  end;
  Result := (mPosition >= 0) and FindToken(AContext, ADecl.StartOffset, ADecl.EndOffset, AName, mToken);
  if not Result then
  begin
    Exit;
  end;
  if mPosition < High(ANames) then
  begin
    Result := FindToken(AContext, mToken.Offset + Length(mToken.Text), ADecl.EndOffset, ANames[mPosition + 1],
      mNeighbour);
    AStart := mToken.Offset;
    AStop := mNeighbour.Offset;
  end
  else
  begin
    Result := FindToken(AContext, ADecl.StartOffset, ADecl.EndOffset, ANames[mPosition - 1], mNeighbour);
    AStart := mNeighbour.Offset + Length(mNeighbour.Text);
    AStop := mToken.Offset + Length(mToken.Text);
  end;
end;

/// <summary>Entfernt die ganze Deklaration ADecl; als letzte Deklaration entfällt der leer gewordene
/// var-Abschnitt mit.</summary>
function DeclarationFix(const ACache: IRuleDerivedCache; const AContext: TRuleContext; ASection,
  ADecl: TSyntaxNode; const ATitle: string; out AFix: TRuleFix): Boolean;
var
  mStart, mLineStart, mLineEnd: Integer;
begin
  mStart := ADecl.StartOffset;
  if ASection.ChildCount = 1 then
  begin
    mStart := ASection.StartOffset;
  end;
  Result := WholeLines(AContext.Text, mStart, ADecl.EndOffset, mLineStart, mLineEnd);
  if Result then
  begin
    AFix := TRuleFix.Create(ATitle, [TRuleEdit.Create(TRuleDerived.OffsetRange(ACache, AContext, mLineStart,
      mLineEnd), '')]);
  end;
end;

/// <summary>Korrektur, die AName aus ADecl entfernt (ASection = nil bei Inline-Variablen);
/// False, wenn keine sichere Korrektur möglich ist.</summary>
function RemoveVarFix(const ACache: IRuleDerivedCache; const AContext: TRuleContext; ASection, ADecl: TSyntaxNode;
  const AName: string; out AFix: TRuleFix): Boolean;
var
  mNames: TArray<string>;
  mTitle: string;
  mStart, mStop: Integer;
begin
  mTitle := cTexts[TUnusedText.RemoveVariable].Fmt([AName]);
  mNames := SplitNames(ADecl.Name);
  if ADecl.Kind = TSyntaxKind.InlineVar then
  begin
    Result := InlineVarFix(ACache, AContext, ADecl, mTitle, AFix);
  end
  // Nur den Namen aus der Liste nehmen: "I, J: Integer" wird "J: Integer".
  else if Length(mNames) > 1 then
  begin
    Result := ListNameSpan(AContext, ADecl, mNames, AName, mStart, mStop);
    if Result then
    begin
      AFix := TRuleFix.Create(mTitle, [TRuleEdit.Create(TRuleDerived.OffsetRange(ACache, AContext, mStart, mStop),
        '')]);
    end;
  end
  else
  begin
    Result := DeclarationFix(ACache, AContext, ASection, ADecl, mTitle, AFix);
  end;
end;

{ TUnusedLocalCheck }

procedure TUnusedLocalCheck.CheckDecl(ASection, ADecl: TSyntaxNode);
var
  mName, mMessage: string;
  mConfidence: TRuleConfidence;
  mFix: TRuleFix;
begin
  for mName in SplitNames(ADecl.Name) do
  begin
    if IsIgnored(mName, FPatterns) or not IsUnused(FContext, FInfo, FUses, mName, ADecl.EndOffset,
      mConfidence) then
    begin
      Continue;
    end;
    mMessage := cTexts[TUnusedText.LocalUnused].Fmt([mName]);
    if RemoveVarFix(FCache, FContext, ASection, ADecl, mName, mFix) then
    begin
      FReport.Add(NameRange(FContext, ADecl, mName), mMessage, mConfidence, [mFix]);
    end
    else
    begin
      FReport.Add(NameRange(FContext, ADecl, mName), mMessage, mConfidence);
    end;
  end;
end;

procedure TUnusedLocalCheck.CheckRoutine(ARoutine: TSyntaxNode);
var
  mDecl: TSyntaxNode;
  mInlineVars: TArray<TSyntaxNode>;
begin
  // Lokale Routinen gehören dazu: sie dürfen Variablen der äußeren verwenden.
  CollectRoutineUses(ARoutine, [TSyntaxKind.Block, TSyntaxKind.RoutineDecl]);
  for mDecl in VarDecls(ARoutine) do
  begin
    CheckDecl(mDecl.Parent, mDecl);
  end;
  mInlineVars := nil;
  CollectInlineVars(FInfo.Block, mInlineVars);
  for mDecl in mInlineVars do
  begin
    CheckDecl(nil, mDecl);
  end;
end;

procedure TUnusedLocalRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TUnusedLocalCheck;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mCheck := TUnusedLocalCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

{ TUnusedParameterRule }

function TUnusedParameterRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('unused-parameter', TRuleSeverity.Hint, cTexts[TUnusedText.ParamTitle].Text);
end;

/// <summary>Wird ANode als Wert verwendet (Zuweisung, Argument, @) statt aufgerufen?</summary>
function IsValueUse(ANode: TSyntaxNode): Boolean;
var
  Parent: TSyntaxNode;
begin
  // Self.Handler: die ganze Kette zählt.
  while (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.MemberAccess) and
    (ANode.Parent[ANode.Parent.ChildCount - 1] = ANode) do
  begin
    ANode := ANode.Parent;
  end;
  Parent := ANode.Parent;
  if Parent = nil then
  begin
    Exit(False);
  end;
  case Parent.Kind of
    TSyntaxKind.AddressOf:
      Result := True;
    TSyntaxKind.AssignStatement:
      Result := Parent[0] <> ANode;
    TSyntaxKind.Call:
      Result := Parent[0] <> ANode;
    // Tabellen: array[…] of TFix = (A, B), Record-Konstante (Name: 'x'; Lauf: A), [A, B], X: TFix = A (#1451).
    // Eine Routine mit Parametern ohne Klammern ist dort kein Aufruf.
    TSyntaxKind.ParenExpr, TSyntaxKind.SetConstructor, TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl,
    TSyntaxKind.InlineVar, TSyntaxKind.InlineConst:
      Result := True;
  else
    Result := False;
  end;
end;

/// <summary>Alle Namen unter ARoot, die als Wert verwendet werden, klein geschrieben in ANames.</summary>
procedure CollectValueNames(ARoot: TSyntaxNode; ANames: TNameSet);
begin
  // Iterativ (Bericht M1).
  ARoot.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      // Auch Objekt.Methode (Writer.OnFindMethodName := Namer.FindMethodName): Der Name steht am MemberAccess.
      if (AVisited.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and IsValueUse(AVisited) then
      begin
        ANames.AddOrSetValue(LowerCase(AVisited.Name), True);
      end;
      Result := TSyntaxSearchStep.Descend;
    end);
end;

/// <summary>Parameterliste der Routine; False ohne Kopf oder ohne Parameter.</summary>
function RoutineParameters(ARoutine: TSyntaxNode; out AHeader, AParams: TSyntaxNode): Boolean;
begin
  AParams := nil;
  AHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if AHeader <> nil then
  begin
    AParams := AHeader.FindChild(TSyntaxKind.Parameters);
  end;
  Result := AParams <> nil;
end;

/// <summary>Hat die Routine einen Parameter namens Sender (Ereignis-Handler)?</summary>
function HasSenderParameter(AParams: TSyntaxNode): Boolean;
var
  mIndex: Integer;
  mName: string;
begin
  Result := False;
  for mIndex := 0 to AParams.ChildCount - 1 do
  begin
    for mName in SplitNames(AParams[mIndex].Name) do
    begin
      Result := Result or SameText(mName, 'Sender');
    end;
  end;
end;

{ TUnusedParameterCheck }

destructor TUnusedParameterCheck.Destroy;
begin
  FValueNames.Free;
  inherited Destroy;
end;

function TUnusedParameterCheck.UsedAsValue(const AName: string): Boolean;
begin
  if FValueNames = nil then
  begin
    FValueNames := TNameSet.Create;
    CollectValueNames(FContext.Tree.Root, FValueNames);
  end;
  Result := FValueNames.ContainsKey(LowerCase(AName));
end;

/// <summary>Ist die Signatur von außen vorgegeben oder wird die Routine als Wert verwendet?</summary>
function TUnusedParameterCheck.SignatureGiven(ARoutine: TSyntaxNode): Boolean;
begin
  Result := ((Pos('.', ARoutine.Name) > 0) and MethodSignatureFixed(FContext.Tree.Root, ARoutine.Name)) or
    UsedAsValue(ShortName(ARoutine.Name));
end;

procedure TUnusedParameterCheck.CheckParameter(AHeader, AParam: TSyntaxNode);
var
  mName: string;
  mConfidence: TRuleConfidence;
begin
  for mName in SplitNames(AParam.Name) do
  begin
    if IsIgnored(mName, FPatterns) or not IsUnused(FContext, FInfo, FUses, mName, AHeader.EndOffset,
      mConfidence) then
    begin
      Continue;
    end;
    // Parameter sind unsicherer als Variablen: die Signatur kann von außen vorgegeben sein.
    if mConfidence = TRuleConfidence.High then
    begin
      mConfidence := TRuleConfidence.Medium;
    end;
    FReport.Add(NameRange(FContext, AParam, mName), cTexts[TUnusedText.ParamUnused].Fmt([mName]),
      mConfidence);
  end;
end;

procedure TUnusedParameterCheck.CheckRoutine(ARoutine: TSyntaxNode);
var
  mHeader, mParams: TSyntaxNode;
  mIndex: Integer;
begin
  if not RoutineParameters(ARoutine, mHeader, mParams) or HasSenderParameter(mParams) or
    SignatureGiven(ARoutine) then
  begin
    Exit;
  end;
  CollectRoutineUses(ARoutine, [TSyntaxKind.Block, TSyntaxKind.RoutineDecl, TSyntaxKind.VarSection]);
  for mIndex := 0 to mParams.ChildCount - 1 do
  begin
    if mParams[mIndex].Kind = TSyntaxKind.Parameter then
    begin
      CheckParameter(mHeader, mParams[mIndex]);
    end;
  end;
end;

procedure TUnusedParameterRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TUnusedParameterCheck;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mCheck := TUnusedParameterCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

{ TUnusedAssignmentRule }

function TUnusedAssignmentRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('unused-assignment', TRuleSeverity.Hint, cTexts[TUnusedText.AssignedTitle].Text);
end;

/// <summary>Kommt AName in lokalen Routinen oder anonymen Methoden unter ANode vor (ANode selbst zählt nicht)?</summary>
function UsedInNested(ANode: TSyntaxNode; const AName: string): Boolean;
var
  Root: TSyntaxNode;
  Name: string;
begin
  Root := ANode;
  Name := AName;
  // Iterativ (Bericht M1).
  Result := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      if (AVisited = Root) or not (AVisited.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) then
      begin
        Exit(TSyntaxSearchStep.Descend);
      end;
      if MentionsName(AVisited, Name) then
      begin
        Exit(TSyntaxSearchStep.Found);
      end;
      Result := TSyntaxSearchStep.Skip;
    end) <> nil;
end;

/// <summary>Hat die var-Deklaration ADecl einen Interface-Typ (IFoo nach Delphi-Brauch)? Zuweisungen an solche
/// Variablen wirken über den Referenzzähler: Activity := TAtlasActivity.Scope(…) hält einen Bereich bis zum Ende
/// der Routine, Writer := nil gibt den Schreiber vorzeitig frei. Wie Delphis H2077 schweigt die Regel dort (#1109).</summary>
function IsInterfaceTyped(ADecl: TSyntaxNode): Boolean;
var
  TypeNode: TSyntaxNode;
  TypeName: string;
begin
  TypeNode := ADecl.FindChild(TSyntaxKind.TypeReference);
  if TypeNode = nil then
  begin
    Exit(False);
  end;
  TypeName := TypeNode.Name;
  if LastDelimiter('.', TypeName) > 0 then
  begin
    TypeName := Copy(TypeName, LastDelimiter('.', TypeName) + 1, MaxInt);
  end;
  Result := (Length(TypeName) > 1) and (TypeName[1] = 'I') and CharInSet(TypeName[2], ['A'..'Z']);
end;

/// <summary>Leert die Zuweisung AWrite ihr Ziel (X := nil, X := '', X := Default(T), X := T.Empty)?</summary>
function ClearsValue(const AText: string; AWrite: TSyntaxNode): Boolean;
var
  Value: string;
begin
  if (AWrite.Kind <> TSyntaxKind.AssignStatement) or (AWrite.ChildCount < 2) then
  begin
    Exit(False);
  end;
  Value := Copy(AText, AWrite[1].StartOffset + 1, AWrite[1].EndOffset - AWrite[1].StartOffset);
  Value := StringReplace(StringReplace(StringReplace(StringReplace(Value, ' ', '', [rfReplaceAll]), #9, '',
    [rfReplaceAll]), #13, '', [rfReplaceAll]), #10, '', [rfReplaceAll]);
  Result := SameText(Value, 'nil') or (Value = '''''') or (StartsText('Default(', Value) and EndsText(')', Value)) or
    EndsText('.Empty', Value) or EndsText('.Empty()', Value);
end;

/// <summary>Ordnet ANode als Schreib- oder Lesezugriff auf ATarget ein.</summary>
procedure ClassifyAccess(ANode: TSyntaxNode; const ATarget: string; AWrites, AReads: TList<TSyntaxNode>);
begin
  if (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, ATarget) then
  begin
    if (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.AssignStatement) and (ANode.Parent[0] = ANode) then
    begin
      AWrites.Add(ANode.Parent);
    end
    else
    begin
      AReads.Add(ANode);
    end;
  end
  else if (ANode.Kind = TSyntaxKind.InlineVar) and (ANode.ChildCount > 0) and
    MatchText(ATarget, SplitNames(ANode.Name)) then
  begin
    AWrites.Add(ANode);
  end;
end;

/// <summary>Schreib- und Lesezugriffe auf ATarget unter ARoot, ohne lokale Routinen und anonyme Methoden.
/// </summary>
procedure CollectAccesses(ARoot: TSyntaxNode; const ATarget: string; AWrites, AReads: TList<TSyntaxNode>);
var
  mTarget: string;
  mWrites, mReads: TList<TSyntaxNode>;
begin
  // Iterativ (Bericht M1). Nur Locals dieser Routine gehen in die anonyme Methode.
  mTarget := ATarget;
  mWrites := AWrites;
  mReads := AReads;
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := not (ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]);
      if Result then
      begin
        ClassifyAccess(ANode, mTarget, mWrites, mReads);
      end;
    end);
end;

type
  /// <summary>Ein Lauf von unused-assignment über eine Datei.</summary>
  TUnusedAssignmentCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FCache: IRuleDerivedCache;
    FPatterns: TArray<string>;
    FWrites: TList<TSyntaxNode>;
    FReads: TList<TSyntaxNode>;
    // Typtext je Name (Kleinbuchstaben) der Routine; '' ohne Typangabe (var X := …).
    FTypes: TDictionary<string, string>;
    FManaged: TManagedTypes;
    FRoutine: TSyntaxNode;
    FInfo: TRoutineInfo;
    FGraph: TControlFlowGraph;
    FName: string;
    procedure AddTypes(ADecl: TSyntaxNode);
    function CodeSuffix(const AName: string): string;
    function FlowNodesOf(ANode: TSyntaxNode): TArray<TFlowNode>;
    function ReadReaches(ARead: TSyntaxNode; ADefinition: TFlowNode): Boolean;
    function IsRead(ADefinition: TFlowNode): Boolean;
    function HoldsValue(AWrite: TSyntaxNode): Boolean;
    function Excluded: Boolean;
    function GraphComplete: Boolean;
    function WriteUnread(AWrite: TSyntaxNode): Boolean;
    procedure CheckName;
    function LocalNames: TArray<string>;
    procedure CheckRoutine(ARoutine: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

constructor TUnusedAssignmentCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FPatterns := IgnorePatterns(AContext.Options);
  // Routinen, Signaturen und Graphen teilt der Lauf mit den anderen Regeln (Review P-03).
  FCache := TRuleDerived.Open(AContext);
  FWrites := TList<TSyntaxNode>.Create;
  FReads := TList<TSyntaxNode>.Create;
  FTypes := TDictionary<string, string>.Create;
  FManaged := TManagedTypes.Create(AContext.Tree, AContext.Text, AContext.Index);
end;

destructor TUnusedAssignmentCheck.Destroy;
begin
  FManaged.Free;
  FTypes.Free;
  FReads.Free;
  FWrites.Free;
  inherited Destroy;
end;

procedure TUnusedAssignmentCheck.AddTypes(ADecl: TSyntaxNode);
var
  mPart: string;
begin
  for mPart in SplitNames(ADecl.Name) do
  begin
    FTypes.AddOrSetValue(LowerCase(mPart), FManaged.NodeTypeText(ADecl));
  end;
end;

/// <summary>" (wie H2077)", wenn dcc für den Typ von AName den Hinweis gibt: Typ bekannt und nicht verwaltet.
/// </summary>
function TUnusedAssignmentCheck.CodeSuffix(const AName: string): string;
var
  mTypeText: string;
begin
  Result := '';
  if FTypes.TryGetValue(LowerCase(AName), mTypeText) and (mTypeText <> '') and
    (FManaged.Managed(mTypeText, 0) = '') and not FManaged.CustomManaged(mTypeText, 0) then
  begin
    Result := cTexts[TUnusedText.LikeH2077].Text;
  end;
end;

/// <summary>Flussknoten der nächsten Anweisung um ANode (bei Schleifen mehrere).</summary>
function TUnusedAssignmentCheck.FlowNodesOf(ANode: TSyntaxNode): TArray<TFlowNode>;
var
  mNode: TFlowNode;
begin
  Result := nil;
  while (ANode <> nil) and (Result = nil) do
  begin
    for mNode in FGraph.Nodes do
    begin
      if mNode.Syntax = ANode then
      begin
        Result := Result + [mNode];
      end;
    end;
    ANode := ANode.Parent;
  end;
end;

/// <summary>Erreicht ADefinition den Lesezugriff ARead?</summary>
function TUnusedAssignmentCheck.ReadReaches(ARead: TSyntaxNode; ADefinition: TFlowNode): Boolean;
var
  mNode, mDefinition: TFlowNode;
begin
  for mNode in FlowNodesOf(ARead) do
  begin
    for mDefinition in FGraph.ReachingDefinitions(mNode, FName).Definitions do
    begin
      if mDefinition = ADefinition then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

function TUnusedAssignmentCheck.IsRead(ADefinition: TFlowNode): Boolean;
var
  mRead: TSyntaxNode;
begin
  for mRead in FReads do
  begin
    if ReadReaches(mRead, ADefinition) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Erreicht eine andere Zuweisung an FName die Zuweisung AWrite, hält die Variable dort also schon
/// einen Wert?</summary>
function TUnusedAssignmentCheck.HoldsValue(AWrite: TSyntaxNode): Boolean;
var
  mNode, mDefinition: TFlowNode;
begin
  for mNode in FGraph.Nodes do
  begin
    if mNode.Syntax <> AWrite then
    begin
      Continue;
    end;
    for mDefinition in FGraph.ReachingDefinitions(mNode, FName).Definitions do
    begin
      if mDefinition.Syntax <> AWrite then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

function TUnusedAssignmentCheck.Excluded: Boolean;
begin
  Result := IsIgnored(FName, FPatterns) or HasOpaqueUse(FInfo.Block, FName) or UsedInNested(FRoutine, FName) or
    UsedByAbsolute(FContext, FRoutine, FName);
end;

/// <summary>Holt den Graphen der Routine bei Bedarf; nur ein vollständiger taugt.</summary>
function TUnusedAssignmentCheck.GraphComplete: Boolean;
begin
  if FGraph = nil then
  begin
    FGraph := TRuleDerived.Graph(FCache, FContext, FRoutine);
  end;
  Result := FGraph.Complete;
end;

/// <summary>Zuweisungen im finally stehen je Ausgang einmal im Graphen; ungelesen ist AWrite nur, wenn der Wert
/// in keiner erreichbaren Kopie gelesen wird.</summary>
function TUnusedAssignmentCheck.WriteUnread(AWrite: TSyntaxNode): Boolean;
var
  mDefinition: TFlowNode;
  mDefined: Boolean;
begin
  mDefined := False;
  for mDefinition in FGraph.Nodes do
  begin
    if (mDefinition.Syntax = AWrite) and SameText(mDefinition.Defines, FName) and
      (FGraph.IsReachable(mDefinition) = TFlowAnswer.Yes) then
    begin
      if IsRead(mDefinition) then
      begin
        Exit(False);
      end;
      mDefined := True;
    end;
  end;
  Result := mDefined;
end;

procedure TUnusedAssignmentCheck.CheckName;
var
  mWrite: TSyntaxNode;
begin
  if Excluded then
  begin
    Exit;
  end;
  FWrites.Clear;
  FReads.Clear;
  CollectAccesses(FInfo.Block, FName, FWrites, FReads);
  if (FWrites.Count = 0) or not GraphComplete then
  begin
    Exit;
  end;
  for mWrite in FWrites do
  begin
    // Leeren eines gesetzten Werts ist Freigabe (Started := Default(…) am Testende, Lookup := nil vor Free).
    if WriteUnread(mWrite) and not (ClearsValue(FContext.Text, mWrite) and HoldsValue(mWrite)) then
    begin
      FReport.Add(NameRange(FContext, mWrite, FName), cTexts[TUnusedText.NeverRead].Fmt(
        [FName, CodeSuffix(FName)]), TRuleConfidence.High);
    end;
  end;
end;

/// <summary>Namen der Variablen der Routine ohne Interface-Typ; merkt ihre Typen.</summary>
function TUnusedAssignmentCheck.LocalNames: TArray<string>;
var
  mDecl: TSyntaxNode;
  mDecls: TArray<TSyntaxNode>;
begin
  Result := nil;
  FTypes.Clear;
  mDecls := VarDecls(FRoutine);
  CollectInlineVars(FInfo.Block, mDecls);
  for mDecl in mDecls do
  begin
    if not IsInterfaceTyped(mDecl) then
    begin
      Result := Result + SplitNames(mDecl.Name);
      AddTypes(mDecl);
    end;
  end;
end;

procedure TUnusedAssignmentCheck.CheckRoutine(ARoutine: TSyntaxNode);
var
  mName: string;
begin
  // Mit bedingter Kompilierung ist nicht eindeutig, welche Lesezugriffe es gibt.
  if not RoutineInfo(FContext, ARoutine, FInfo) or FInfo.Conditionals then
  begin
    Exit;
  end;
  FRoutine := ARoutine;
  FGraph := nil;
  for mName in LocalNames do
  begin
    FName := mName;
    CheckName;
  end;
end;

procedure TUnusedAssignmentCheck.Run;
var
  mRoutine: TSyntaxNode;
begin
  for mRoutine in TRuleDerived.Routines(FCache, FContext) do
  begin
    CheckRoutine(mRoutine);
  end;
end;

procedure TUnusedAssignmentRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TUnusedAssignmentCheck;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mCheck := TUnusedAssignmentCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

procedure RegisterUnusedRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TUnusedLocalRule.Create);
  ARegistry.Register(TUnusedParameterRule.Create);
  ARegistry.Register(TUnusedAssignmentRule.Create);
  ARegistry.Register(TDuplicateAssignmentRule.Create);
  ARegistry.Register(TEmptyRoutineRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Unused', cTexts);

end.
