unit Atlas.Common.Rules.Builtin.XmlDoc;

// xmldoc-mismatch (#979, Gruppe Stil und Metriken): ///-Kommentare, die nicht
// zur Signatur passen oder kein wohlgeformtes XML sind, wie die Compiler-
// warnungen W1201 bis W1208 mit eingeschalteter XML-Dokumentation.
//
// Einen Code nennt die Meldung nur, wo dcc ihn meldet (#1383): nur für
// Kommentare im interface-Teil einer Unit (nur die dokumentiert dcc) und nur
// für Formen, die dcc dort beanstandet. Delphi 13 meldet ein fremdes Zeichen
// hinter dem Tagnamen (W1205), unbekannte cref (W1206) und die Signatur
// (W1207, W1208); "<" mit Leerzeichen, unbekannte Entitäten, leere
// Attributwerte und offene Tags übersetzt es still (Tests/Compilermeldungen).
//
// Wohlgeformt: "<" oder "&" ohne gültiges Tag bzw. Entität,
// unbekannte Entität, Attributwert ohne Anführungszeichen, nicht geschlossene
// und überzählige Endtags. Korrektur: Zeichen maskieren, Anführungszeichen
// setzen, Endtag ergänzen oder entfernen; ein Tag ohne Attribute und Inhalt
// mit fremdem Namen (TList<T>) wird zu Text. Nach einem Fehler im Aufbau
// prüft die Regel den Block nicht weiter, Folgefehler wären Rauschen.
//
// Signatur (W1207, W1208): <param> zu einem Parameter, den es nicht gibt;
// fehlende <param>, wenn der Block überhaupt Parameter beschreibt (wie
// W1208 „but other parameters do“); <returns> an einer Routine ohne Ergebnis
// und fehlendes <returns> an einer Funktion, deren Block Parameter beschreibt
// (beides nur mit checkReturns). Mit <inheritdoc/> fehlt nichts. Korrektur:
// unbekannte <param> der Reihe nach auf die fehlenden umbenennen, weitere
// fehlende als leere Zeilen in Signaturreihenfolge ergänzen, überzählige und
// <returns> an Prozeduren entfernen, <returns> ergänzen.
//
// cref (W1206): Ziele über den Index wie der Hover (TNameResolver.LocateCref).
// Still ohne Index, wenn eine Unit aus uses fehlt, bei generischen Zielen,
// Unit-Namen und Typen mit unbekannten Vorfahren. Korrektur: das ähnlichste
// Symbol (TTextFuzzy.Closest), sofern es sich auflösen lässt.
//
// requirePublic: public- und published-Methoden und -Properties von Typen im
// interface ohne ///-Kommentar; override und Properties ohne Typ (geerbte
// Doku) zählen nicht. Korrektur: Gerüst wie nach "///" (#88).

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cXmlDocMismatchRuleId = 'xmldoc-mismatch';

type
  TXmlDocMismatchRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterXmlDocRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Pascal.XmlDoc,
  Atlas.Common.Rules.Builtin.XmlDoc.Scanner,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.UnresolvedNames,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.DocComments,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Derived,
  Atlas.Text.Lines,
  Atlas.Text.Fuzzy,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TXmlDocText = (AndSep, NoDocComment, CreateDoc, CrefNoSymbol, CrefMeant, SetCref, ReturnsNoResult, ReturnsMissing,
    MatchSignature, Title, DoesNotExist, NotDescribed, NotDescribedMany, LikeCodeDot, LikeCodeParen);

const
  cTexts: array[TXmlDocText] of TAtlasText = (
    (De: ' und '; En: ' and '),
    (De: 'Öffentliches Mitglied %s hat keinen Doku-Kommentar.'; En: 'Public member %s has no doc comment.'),
    (De: 'Doku-Kommentar erzeugen'; En: 'Create doc comment'),
    (De: 'cref "%s" zeigt auf kein Symbol.'; En: 'cref "%s" points to no symbol.'),
    (De: ' Gemeint ist wohl %s.'; En: ' %s is probably meant.'),
    (De: 'cref auf %s setzen'; En: 'Set cref to %s'),
    (De: '<returns> steht an einer Routine ohne Ergebnis'; En: '<returns> is on a routine without result'),
    (De: '<returns> fehlt'; En: '<returns> is missing'),
    (De: 'Doku an die Signatur anpassen'; En: 'Adapt the doc to the signature'),
    (De: 'XMLDoc passt nicht zur Signatur oder ist kein wohlgeformtes XML';
     En: 'XMLDoc does not match the signature or is not well-formed XML'),
    (De: '%s gibt es nicht'; En: '%s does not exist'),
    (De: '%s ist nicht beschrieben'; En: '%s is not described'),
    (De: '%s sind nicht beschrieben'; En: '%s are not described'),
    (De: ' (wie %s).'; En: ' (like %s).'),
    (De: ' (wie %s)'; En: ' (like %s)'));

{$SCOPEDENUMS OFF}

const
  cRoutineWords: array[0..5] of string = ('class', 'function', 'procedure', 'constructor', 'destructor', 'operator');

type
  /// <summary>Folge von ///-Zeilen: Inhalt ohne "///", Zeilen mit #10 verbunden.</summary>
  TDocBlock = record
    Xml: string;
    /// <summary>Je Zeile: Anfang im XML (1-basiert), Offset im Dokument (0-basiert) und Dokumentzeile.</summary>
    Starts: TArray<Integer>;
    Offsets: TArray<Integer>;
    Lines: TArray<Integer>;
    Indent: string;
    FirstToken: Integer;
    LastToken: Integer;
    /// <summary>Offset im Dokument zum Zeichen AIndex des XML.</summary>
    function OffsetOf(AIndex: Integer): Integer;
    /// <summary>Zeile des Blocks (ab 0) zum Zeichen AIndex des XML.</summary>
    function RowOf(AIndex: Integer): Integer;
    /// <summary>Steht in der Zeile von AStart vor AStart und in der von AStop ab AStop nur Leerraum?</summary>
    function OwnsLines(AStart, AStop: Integer): Boolean;
  end;

  TDocSignature = record
    Params: TArray<string>;
    HasResult: Boolean;
  end;

function TDocBlock.RowOf(AIndex: Integer): Integer;
begin
  Result := High(Starts);
  while (Result > 0) and (Starts[Result] > AIndex) do
  begin
    Dec(Result);
  end;
end;

function TDocBlock.OffsetOf(AIndex: Integer): Integer;
var
  mRow: Integer;
begin
  mRow := RowOf(AIndex);
  Result := Offsets[mRow] + AIndex - Starts[mRow];
end;

function TDocBlock.OwnsLines(AStart, AStop: Integer): Boolean;
var
  mIndex: Integer;
begin
  mIndex := Starts[RowOf(AStart)];
  while mIndex < AStart do
  begin
    if not CharInSet(Xml[mIndex], [' ', #9]) then
    begin
      Exit(False);
    end;
    Inc(mIndex);
  end;
  mIndex := AStop;
  while (mIndex <= Length(Xml)) and (Xml[mIndex] <> #10) do
  begin
    if not CharInSet(Xml[mIndex], [' ', #9]) then
    begin
      Exit(False);
    end;
    Inc(mIndex);
  end;
  Result := True;
end;

{ Blöcke und Deklarationen }

function IsDocToken(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.Comment) and StartsStr('///', AToken.Text) and
    not StartsStr('////', AToken.Text);
end;

/// <summary>Alle ///-Blöcke: aufeinanderfolgende Zeilen, in denen der Kommentar das erste Token ist.</summary>
function DocBlocks(const ATokens: TArray<TPascalToken>; const ALines: TArray<string>): TArray<TDocBlock>;
var
  mIndex: Integer;
  mBlock: TDocBlock;
  mLine: string;

  function StartsLine(AIndex: Integer): Boolean;
  begin
    Result := (AIndex = 0) or (ATokens[AIndex - 1].EndPos.Line < ATokens[AIndex].StartPos.Line);
  end;

begin
  Result := nil;
  mIndex := 0;
  while mIndex <= High(ATokens) do
  begin
    if not IsDocToken(ATokens[mIndex]) or not StartsLine(mIndex) then
    begin
      Inc(mIndex);
      Continue;
    end;
    mBlock := Default(TDocBlock);
    mBlock.FirstToken := mIndex;
    mLine := '';
    if ATokens[mIndex].StartPos.Line <= High(ALines) then
    begin
      mLine := ALines[ATokens[mIndex].StartPos.Line];
    end;
    mBlock.Indent := Copy(mLine, 1, ATokens[mIndex].StartPos.Character);
    repeat
      if mBlock.Xml <> '' then
      begin
        mBlock.Xml := mBlock.Xml + #10;
      end;
      mBlock.Starts := mBlock.Starts + [Length(mBlock.Xml) + 1];
      mBlock.Offsets := mBlock.Offsets + [ATokens[mIndex].Offset + 3];
      mBlock.Lines := mBlock.Lines + [ATokens[mIndex].StartPos.Line];
      mBlock.Xml := mBlock.Xml + Copy(ATokens[mIndex].Text, 4, MaxInt);
      mBlock.LastToken := mIndex;
      Inc(mIndex);
    until (mIndex > High(ATokens)) or not IsDocToken(ATokens[mIndex]) or
      (ATokens[mIndex].StartPos.Line <> ATokens[mIndex - 1].StartPos.Line + 1);
    Result := Result + [mBlock];
  end;
end;

/// <summary>Erstes Token der Deklaration hinter dem Block (Attribute übersprungen); -1 ohne.</summary>
function DeclarationToken(const ATokens: TArray<TPascalToken>; ALast: Integer): Integer;
var
  mDepth: Integer;
begin
  Result := ALast + 1;
  while (Result <= High(ATokens)) and ATokens[Result].IsSymbol('[') do
  begin
    mDepth := 0;
    repeat
      if ATokens[Result].IsSymbol('[') then
      begin
        Inc(mDepth);
      end
      else if ATokens[Result].IsSymbol(']') then
      begin
        Dec(mDepth);
      end;
      Inc(Result);
    until (Result > High(ATokens)) or (mDepth = 0);
  end;
  if Result > High(ATokens) then
  begin
    Result := -1;
  end;
end;

// Iterativ (tiefe Bäume sprengen den Stapel nicht).
procedure CollectDeclarations(ARoot: TSyntaxNode; AMap: TDictionary<Integer, TSyntaxNode>);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if (mNode.Kind in [TSyntaxKind.RoutineHeader, TSyntaxKind.PropertyDecl, TSyntaxKind.TypeDecl,
        TSyntaxKind.Field, TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl]) and not AMap.ContainsKey(mNode.StartOffset) then
      begin
        AMap.Add(mNode.StartOffset, mNode);
      end;
      if mNode.Kind = TSyntaxKind.Block then
      begin
        Continue;
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

function SignatureOf(AHeader: TSyntaxNode): TDocSignature;
var
  mParameters: TSyntaxNode;
  mIndex: Integer;
  mName: string;
begin
  Result := Default(TDocSignature);
  for mIndex := 0 to AHeader.ChildCount - 1 do
  begin
    if AHeader[mIndex].Kind = TSyntaxKind.TypeReference then
    begin
      Result.HasResult := True;
    end;
  end;
  mParameters := AHeader.FindChild(TSyntaxKind.Parameters);
  if mParameters = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mParameters.ChildCount - 1 do
  begin
    if mParameters[mIndex].Kind = TSyntaxKind.Parameter then
    begin
      for mName in mParameters[mIndex].Name.Split([',']) do
      begin
        Result.Params := Result.Params + [Trim(mName)];
      end;
    end;
  end;
end;

/// <summary>Typ, in dem ANode deklariert ist ("TAussen.TInnen"), bei TFoo.Bar im implementation-Teil "TFoo";
/// bei Typen der Typ selbst.</summary>
function ContainerOf(ANode: TSyntaxNode): string;
var
  mNode: TSyntaxNode;
begin
  Result := '';
  if (ANode.Kind = TSyntaxKind.RoutineHeader) and (LastDelimiter('.', ANode.Name) > 0) then
  begin
    Exit(Copy(ANode.Name, 1, LastDelimiter('.', ANode.Name) - 1));
  end;
  mNode := ANode;
  while mNode <> nil do
  begin
    if mNode.Kind = TSyntaxKind.TypeDecl then
    begin
      if Result = '' then
      begin
        Result := mNode.Name;
      end
      else
      begin
        Result := mNode.Name + '.' + Result;
      end;
    end;
    mNode := mNode.Parent;
  end;
end;

/// <summary>Name der Deklaration ab Token AStart (hinter class, function …), bei TFoo.Bar die ganze Kette.</summary>
function NameRange(const ATokens: TArray<TPascalToken>; AStart: Integer; out AFrom, ATo: Integer): Boolean;
var
  mIndex: Integer;
begin
  mIndex := AStart;
  while (mIndex <= High(ATokens)) and ((ATokens[mIndex].Kind = TPascalTokenKind.Comment) or
    MatchText(ATokens[mIndex].Text, cRoutineWords) or SameText(ATokens[mIndex].Text, 'property')) do
  begin
    Inc(mIndex);
  end;
  Result := (mIndex <= High(ATokens)) and (ATokens[mIndex].Kind in [TPascalTokenKind.Identifier,
    TPascalTokenKind.Keyword]);
  if not Result then
  begin
    Exit;
  end;
  AFrom := mIndex;
  ATo := mIndex;
  while (ATo + 2 <= High(ATokens)) and ATokens[ATo + 1].IsSymbol('.') and
    (ATokens[ATo + 2].Kind = TPascalTokenKind.Identifier) do
  begin
    Inc(ATo, 2);
  end;
end;

/// <summary>Edits nach Anfang sortiert (stabil), wie Clients und Tests sie von hinten anwenden.</summary>
function Sorted(const AEdits: TArray<TTextEdit>): TArray<TTextEdit>;
var
  mIndex, mPosition: Integer;
  mEdit: TTextEdit;

  function Before(const A, B: TTextPosition): Boolean;
  begin
    Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
  end;

begin
  Result := Copy(AEdits);
  for mIndex := 1 to High(Result) do
  begin
    mEdit := Result[mIndex];
    mPosition := mIndex;
    while (mPosition > 0) and Before(mEdit.Range.StartPos, Result[mPosition - 1].Range.StartPos) do
    begin
      Result[mPosition] := Result[mPosition - 1];
      Dec(mPosition);
    end;
    Result[mPosition] := mEdit;
  end;
end;

function Joined(const ANames: TArray<string>): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(ANames) do
  begin
    if mIndex = 0 then
    begin
      Result := ANames[mIndex];
    end
    else if mIndex = High(ANames) then
    begin
      Result := Result + cTexts[TXmlDocText.AndSep].Text + ANames[mIndex];
    end
    else
    begin
      Result := Result + ', ' + ANames[mIndex];
    end;
  end;
end;

function Contains(const ANames: TArray<string>; const AName: string): Boolean;
var
  mName: string;
begin
  for mName in ANames do
  begin
    if SameText(mName, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function Overrides(AMember: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to AMember.ChildCount - 1 do
  begin
    if (AMember[mIndex].Kind = TSyntaxKind.Directive) and SameText(AMember[mIndex].Name, 'override') then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Medium mit Include-Dateien: Ein cref-Ziel kann dort deklariert sein.</summary>
function IncludeLevel(const ATokens: TArray<TPascalToken>): TRuleConfidence;
var
  mToken: TPascalToken;
begin
  Result := TRuleConfidence.High;
  for mToken in ATokens do
  begin
    if (mToken.Kind = TPascalTokenKind.Directive) and (StartsText('{$I ', mToken.Text) or
      StartsText('{$INCLUDE ', mToken.Text)) then
    begin
      Result := TRuleConfidence.Medium;
    end;
  end;
end;

/// <summary>Lassen sich cref-Ziele prüfen: Index vorhanden und alle Units aus uses bekannt?</summary>
function CrefsKnown(const AContext: TRuleContext; const ATokens: TArray<TPascalToken>): Boolean;
begin
  Result := TUnresolvedNames.Available(AContext.Index) and TUnresolvedNames.UsesKnown(AContext.Index,
    TUsesClauses.UsedUnits(ATokens), AContext.Namespaces, AContext.EnsureUnit);
end;

/// <summary>Ist der Name sicher nicht prüfbar? Generische Ziele und eingebaute Namen bleiben offen.</summary>
function Unverifiable(const AName: string): Boolean;
begin
  Result := (AName = '') or (LastDelimiter('<>{}`', AName) > 0) or TResolverText.IsBuiltinTypeName(AName) or
    TUnresolvedNames.IsIntrinsic(AName);
end;

/// <summary>Zerlegt einen cref-Wert in Präfix ("T:"), Namen und Parameterliste ("(…)").</summary>
procedure SplitCref(const AValue: string; out APrefix, AName, ARest: string);
var
  mValue: string;
begin
  mValue := AValue;
  APrefix := '';
  ARest := '';
  if (Length(mValue) > 2) and (mValue[2] = ':') then
  begin
    APrefix := Copy(mValue, 1, 2);
    mValue := Copy(mValue, 3, MaxInt);
  end;
  if Pos('(', mValue) > 0 then
  begin
    ARest := Copy(mValue, Pos('(', mValue), MaxInt);
    mValue := Copy(mValue, 1, Pos('(', mValue) - 1);
  end;
  AName := Trim(mValue);
end;

function CandidateNames(const ASymbols: TArray<TResolvedSymbol>): TArray<string>;
var
  mSymbol: TResolvedSymbol;
begin
  Result := nil;
  for mSymbol in ASymbols do
  begin
    Result := Result + [mSymbol.Name];
  end;
end;

type
  TDocCrefCheck = class;

  /// <summary>Ein Lauf von xmldoc-mismatch über eine Unit.</summary>
  TXmlDocCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FCache: IRuleDerivedCache;
    FTokens: TArray<TPascalToken>;
    FLines: TArray<string>;
    FLineBreak: string;
    FCheckReturns: Boolean;
    FRequirePublic: Boolean;
    FDeclarations: TDictionary<Integer, TSyntaxNode>;
    FDocumented: TDictionary<TSyntaxNode, Boolean>;
    /// <summary>nil, wenn sich cref-Ziele nicht prüfen lassen.</summary>
    FCrefs: TDocCrefCheck;
    // interface-Teil der Unit [Start, Stop); leer ohne (Programm, Paket).
    FInterfaceStart: Integer;
    FInterfaceStop: Integer;
    procedure FindInterface;
    /// <summary>Dokumentiert dcc die Deklaration hinter ABlock (interface-Teil einer Unit)? Nur dann meldet es
    /// W1201 bis W1208 (#1383).</summary>
    function CompilerChecks(const ABlock: TDocBlock): Boolean;
    function ReplacementEdit(const ABlock: TDocBlock; const AReplacement: TDocReplacement): TRuleEdit;
    procedure ReportFlaws(const ABlock: TDocBlock; const AFlaws: TArray<TDocFlaw>);
    /// <summary>Deklaration hinter dem Block; nil ohne.</summary>
    function DeclarationAfter(const ABlock: TDocBlock): TSyntaxNode;
    /// <summary>Meldet die Verstöße gegen XML; False, wenn der Aufbau kaputt ist.</summary>
    function ScanBlock(const ABlock: TDocBlock; out AElements: TArray<TDocElement>): Boolean;
    procedure CheckSignature(const ABlock: TDocBlock; const AElements: TArray<TDocElement>; AHeader: TSyntaxNode);
    procedure CheckCrefs(const ABlock: TDocBlock; const AElements: TArray<TDocElement>; ADeclaration: TSyntaxNode);
    procedure CheckBlock(const ABlock: TDocBlock);
    /// <summary>Braucht AMember (in AOwner) einen Doku-Kommentar?</summary>
    function NeedsDoc(AOwner, AMember: TSyntaxNode): Boolean;
    /// <summary>Zeile für das Gerüst: über den Attributen der Deklaration.</summary>
    function SkeletonRow(AMember: TSyntaxNode): Integer;
    procedure ReportUndocumented(AMember: TSyntaxNode);
    procedure CheckPublic(ANode: TSyntaxNode; APublic: Boolean);
    procedure CheckInterfaceMembers;
  public
    /// <summary>AContext mit Baum und Wurzel.</summary>
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
    /// <summary>AMessage mit "(wie ACode)" vor dem Schlusspunkt, wenn dcc den Block prüft; sonst unverändert.
    /// </summary>
    function WithCode(const ABlock: TDocBlock; const AMessage, ACode: string): string;
    function DeclarationRange(ANode: TSyntaxNode): TTextRange;
    function XmlRange(const ABlock: TDocBlock; AStart, AStop: Integer): TTextRange;
    /// <summary>Element entfernen; füllt es seine Zeilen allein, die ganzen Zeilen.</summary>
    function RemoveEdit(const ABlock: TDocBlock; const AElement: TDocElement): TRuleEdit;
    function DocLine(const ABlock: TDocBlock; const AText: string): string;
  end;

  /// <summary>cref-Ziele (W1206) über den Index wie der Hover.</summary>
  TDocCrefCheck = class
  private
    FOwner: TXmlDocCheck;
    FContext: TRuleContext;
    FReport: IRuleReport;
    /// <summary>Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.</summary>
    FResolver: TNameResolver;
    FFromUnit: TUnitIndex;
    FLevel: TRuleConfidence;
    /// <summary>Vorfahrenkette bis TObject bzw. IInterface bekannt? Sonst kann ein Mitglied geerbt sein.</summary>
    function ChainKnown(const AType: TResolvedSymbol): Boolean;
    /// <summary>Nennt AName (oder ein Anfang davon) eine Unit?</summary>
    function NamesUnit(const AName: string): Boolean;
    /// <summary>Hat der Typ, in dem AName gesucht wird, unbekannte Vorfahren?</summary>
    function OwnerOpen(const AContainer, AName: string): Boolean;
    /// <summary>Lässt sich der cref sicher als fehlend erkennen? Unit-Namen, generische Ziele, eingebaute Namen und
    /// Typen mit unbekannten Vorfahren bleiben offen.</summary>
    function CrefMissing(const AContainer, AName: string): Boolean;
    /// <summary>Namen ähnlicher Länge: Mitglieder hinter dem Typ bzw. Namen im Bereich der Deklaration.</summary>
    function Candidates(const AContainer, AName: string; ADot, AOffset: Integer): TArray<string>;
    /// <summary>Ähnlichster Name mit dem Typ davor; '' ohne.</summary>
    function Replacement(const AContainer, AName: string; AOffset: Integer): string;
  public
    constructor Create(AOwner: TXmlDocCheck; const AContext: TRuleContext; const AReport: IRuleReport;
      AResolver: TNameResolver; const AFromUnit: TUnitIndex; ALevel: TRuleConfidence);
    procedure Check(const ABlock: TDocBlock; const AElement: TDocElement; const AAttribute: TDocAttribute;
      const AContainer: string; AOffset: Integer);
  end;

  /// <summary>Signatur einer Routine gegen ihre &lt;param&gt; und &lt;returns&gt; (W1207, W1208).</summary>
  TDocSignatureCheck = class
  private
    FOwner: TXmlDocCheck;
    FReport: IRuleReport;
    FBlock: TDocBlock;
    FHeader: TSyntaxNode;
    FCheckReturns: Boolean;
    FRequirePublic: Boolean;
    FSignature: TDocSignature;
    // <param> der obersten Ebene und je Eintrag sein Name; FUnknown = Positionen darin ohne Parameter.
    FParams: TArray<TDocElement>;
    FParamNames: TArray<string>;
    FUnknown: TArray<Integer>;
    FMissing: TArray<string>;
    FReturns: TDocElement;
    FHasReturns: Boolean;
    FInherits: Boolean;
    FStrayReturns: Boolean;
    FMissingReturns: Boolean;
    FEdits: TArray<TRuleEdit>;
    // Erste und letzte Blockzeile je Signaturparameter nach der Korrektur, -1 ohne.
    FFirstRows: TArray<Integer>;
    FLastRows: TArray<Integer>;
    // Blockzeile des letzten verbliebenen <param>, -1 ohne.
    FPrevious: Integer;
    FInserts: TDictionary<Integer, string>;
    procedure AddParam(const AElement: TDocElement; const AName: string);
    procedure Collect(const AElements: TArray<TDocElement>);
    procedure FindMissing;
    function Mismatched: Boolean;
    function MessageText: string;
    /// <summary>Position des Eintrags AIndex in FUnknown; -1 ohne.</summary>
    function UnknownPosition(AIndex: Integer): Integer;
    /// <summary>Behält &lt;param&gt; AIndex, umbenannt auf den fehlenden APosition (≥ 0).</summary>
    procedure KeepParam(AIndex, APosition: Integer);
    procedure RenameParams;
    /// <summary>Zeile hinter dem letzten verbliebenen &lt;param&gt;, sonst hinter dem Block.</summary>
    function TailRow: Integer;
    /// <summary>Zeile für den fehlenden Parameter AIndex: hinter dem vorigen beschriebenen, sonst vor dem nächsten,
    /// sonst TailRow.</summary>
    function InsertRow(AIndex: Integer): Integer;
    procedure Insert(ARow: Integer; const AText: string);
    procedure InsertMissing;
    function ReportRange: TTextRange;
  public
    constructor Create(AOwner: TXmlDocCheck; const AReport: IRuleReport; const ABlock: TDocBlock;
      AHeader: TSyntaxNode; ACheckReturns, ARequirePublic: Boolean);
    destructor Destroy; override;
    procedure Run(const AElements: TArray<TDocElement>);
  end;

{ TXmlDocCheck }

constructor TXmlDocCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FCache := TRuleDerived.Open(AContext);
  FTokens := AContext.Tree.Tokens;
  FLines := TTextLines.SplitLines(AContext.Text);
  FLineBreak := TTextLines.LineBreakOf(AContext.Text);
  FCheckReturns := TRuleOptions.Bool(AContext.Options, 'checkReturns', True);
  FRequirePublic := TRuleOptions.Bool(AContext.Options, 'requirePublic', False);
  FDeclarations := TDictionary<Integer, TSyntaxNode>.Create;
  FDocumented := TDictionary<TSyntaxNode, Boolean>.Create;
end;

destructor TXmlDocCheck.Destroy;
begin
  FCrefs.Free;
  FDocumented.Free;
  FDeclarations.Free;
  inherited;
end;

procedure TXmlDocCheck.FindInterface;
var
  mIndex: Integer;
  mRoot: TSyntaxNode;
begin
  mRoot := FContext.Tree.Root;
  for mIndex := 0 to mRoot.ChildCount - 1 do
  begin
    if mRoot[mIndex].Kind = TSyntaxKind.InterfaceSection then
    begin
      FInterfaceStart := mRoot[mIndex].StartOffset;
      FInterfaceStop := mRoot[mIndex].EndOffset;
    end;
  end;
end;

function TXmlDocCheck.CompilerChecks(const ABlock: TDocBlock): Boolean;
var
  mOffset: Integer;
begin
  mOffset := FTokens[ABlock.FirstToken].Offset;
  Result := (mOffset >= FInterfaceStart) and (mOffset < FInterfaceStop);
end;

function TXmlDocCheck.WithCode(const ABlock: TDocBlock; const AMessage, ACode: string): string;
begin
  Result := AMessage;
  if (ACode = '') or not CompilerChecks(ABlock) then
  begin
    Exit;
  end;
  if EndsStr('.', Result) then
  begin
    Result := Copy(Result, 1, Length(Result) - 1) + cTexts[TXmlDocText.LikeCodeDot].Fmt([ACode]);
  end
  else
  begin
    Result := Result + cTexts[TXmlDocText.LikeCodeParen].Fmt([ACode]);
  end;
end;

function TXmlDocCheck.DeclarationRange(ANode: TSyntaxNode): TTextRange;
var
  mFirst, mLast: Integer;
begin
  mFirst := TokenExactly(FTokens, ANode.StartOffset);
  if (mFirst >= 0) and NameRange(FTokens, mFirst, mFirst, mLast) then
  begin
    Result := TTextRange.Create(FTokens[mFirst].StartPos, FTokens[mLast].EndPos);
  end
  else
  begin
    Result := TTextRange.Create(ANode.StartPos, ANode.StartPos);
  end;
end;

function TXmlDocCheck.XmlRange(const ABlock: TDocBlock; AStart, AStop: Integer): TTextRange;
begin
  Result := TRuleDerived.OffsetRange(FCache, FContext, ABlock.OffsetOf(AStart), ABlock.OffsetOf(AStop));
end;

function TXmlDocCheck.ReplacementEdit(const ABlock: TDocBlock; const AReplacement: TDocReplacement): TRuleEdit;
begin
  Result := TRuleEdit.Create(XmlRange(ABlock, AReplacement.Start, AReplacement.Stop), AReplacement.Text);
end;

function TXmlDocCheck.RemoveEdit(const ABlock: TDocBlock; const AElement: TDocElement): TRuleEdit;
begin
  if ABlock.OwnsLines(AElement.Start, AElement.Stop) then
  begin
    Result := TRuleEdit.Create(TTextRange.Create(ABlock.Lines[ABlock.RowOf(AElement.Start)], 0,
      ABlock.Lines[ABlock.RowOf(AElement.Stop)] + 1, 0), '');
  end
  else
  begin
    Result := TRuleEdit.Create(XmlRange(ABlock, AElement.Start, AElement.Stop), '');
  end;
end;

function TXmlDocCheck.DocLine(const ABlock: TDocBlock; const AText: string): string;
begin
  Result := ABlock.Indent + '/// ' + AText + FLineBreak;
end;

procedure TXmlDocCheck.ReportFlaws(const ABlock: TDocBlock; const AFlaws: TArray<TDocFlaw>);
var
  mFlaw: TDocFlaw;
  mReplacement: TDocReplacement;
  mEdits: TArray<TRuleEdit>;
begin
  for mFlaw in AFlaws do
  begin
    mEdits := nil;
    for mReplacement in mFlaw.Replacements do
    begin
      mEdits := mEdits + [ReplacementEdit(ABlock, mReplacement)];
    end;
    if Length(mEdits) > 0 then
    begin
      FReport.Add(XmlRange(ABlock, mFlaw.Start, mFlaw.Stop), WithCode(ABlock, mFlaw.Message, mFlaw.Code),
        [TRuleFix.Create(mFlaw.FixTitle, Sorted(mEdits))]);
    end
    else
    begin
      FReport.Add(XmlRange(ABlock, mFlaw.Start, mFlaw.Stop), WithCode(ABlock, mFlaw.Message, mFlaw.Code));
    end;
  end;
end;

function TXmlDocCheck.DeclarationAfter(const ABlock: TDocBlock): TSyntaxNode;
var
  mToken: Integer;
begin
  Result := nil;
  mToken := DeclarationToken(FTokens, ABlock.LastToken);
  if mToken >= 0 then
  begin
    FDeclarations.TryGetValue(FTokens[mToken].Offset, Result);
  end;
end;

function TXmlDocCheck.ScanBlock(const ABlock: TDocBlock; out AElements: TArray<TDocElement>): Boolean;
var
  mScanner: TDocScanner;
begin
  mScanner := TDocScanner.Create(ABlock.Xml);
  try
    mScanner.Scan;
    ReportFlaws(ABlock, mScanner.Flaws);
    Result := not mScanner.Broken;
    AElements := mScanner.Elements;
  finally
    mScanner.Free;
  end;
end;

procedure TXmlDocCheck.CheckSignature(const ABlock: TDocBlock; const AElements: TArray<TDocElement>;
  AHeader: TSyntaxNode);
var
  mCheck: TDocSignatureCheck;
begin
  mCheck := TDocSignatureCheck.Create(Self, FReport, ABlock, AHeader, FCheckReturns, FRequirePublic);
  try
    mCheck.Run(AElements);
  finally
    mCheck.Free;
  end;
end;

procedure TXmlDocCheck.CheckCrefs(const ABlock: TDocBlock; const AElements: TArray<TDocElement>;
  ADeclaration: TSyntaxNode);
var
  mElement: TDocElement;
  mAttribute: TDocAttribute;
begin
  for mElement in AElements do
  begin
    if not mElement.Attribute('cref', mAttribute) then
    begin
      Continue;
    end;
    if ADeclaration <> nil then
    begin
      FCrefs.Check(ABlock, mElement, mAttribute, ContainerOf(ADeclaration), ADeclaration.StartOffset);
    end
    else
    begin
      FCrefs.Check(ABlock, mElement, mAttribute, '', FTokens[ABlock.FirstToken].Offset);
    end;
  end;
end;

procedure TXmlDocCheck.CheckBlock(const ABlock: TDocBlock);
var
  mDeclaration: TSyntaxNode;
  mElements: TArray<TDocElement>;
begin
  mDeclaration := DeclarationAfter(ABlock);
  if mDeclaration <> nil then
  begin
    FDocumented.AddOrSetValue(mDeclaration, True);
  end;
  if not ScanBlock(ABlock, mElements) then
  begin
    Exit;
  end;
  if (mDeclaration <> nil) and (mDeclaration.Kind = TSyntaxKind.RoutineHeader) then
  begin
    CheckSignature(ABlock, mElements, mDeclaration);
  end;
  if FCrefs <> nil then
  begin
    CheckCrefs(ABlock, mElements, mDeclaration);
  end;
end;

function TXmlDocCheck.NeedsDoc(AOwner, AMember: TSyntaxNode): Boolean;
begin
  Result := (AOwner.Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType,
    TSyntaxKind.InterfaceType]) and not FDocumented.ContainsKey(AMember) and not Overrides(AMember);
  // Property ohne Typ veröffentlicht eine geerbte neu, deren Doku gilt.
  Result := Result and not ((AMember.Kind = TSyntaxKind.PropertyDecl) and
    (AMember.FindChild(TSyntaxKind.TypeReference) = nil));
end;

function TXmlDocCheck.SkeletonRow(AMember: TSyntaxNode): Integer;
var
  mFirst: Integer;
begin
  mFirst := TokenExactly(FTokens, AMember.StartOffset);
  Result := AMember.StartPos.Line;
  while (mFirst > 0) and FTokens[mFirst - 1].IsSymbol(']') do
  begin
    repeat
      Dec(mFirst);
    until (mFirst <= 0) or FTokens[mFirst].IsSymbol('[');
    Result := FTokens[mFirst].StartPos.Line;
  end;
end;

procedure TXmlDocCheck.ReportUndocumented(AMember: TSyntaxNode);
var
  mRow: Integer;
  mSkeleton: TArray<string>;
begin
  // Gerüst über den Attributen.
  mRow := SkeletonRow(AMember);
  mSkeleton := TDocComments.Skeleton(TDocComments.Signature(FLines, AMember.StartPos.Line),
    TTextLines.IndentOf(FLines[mRow]));
  FReport.Add(DeclarationRange(AMember), cTexts[TXmlDocText.NoDocComment].Fmt(
    [AMember.Name]), [TRuleFix.Create(cTexts[TXmlDocText.CreateDoc].Text, [TRuleEdit.Create(TTextRange.Create(mRow,
    0, mRow, 0), TTextLines.JoinLines(mSkeleton, FLineBreak) + FLineBreak)])]);
end;

// requirePublic: öffentliche Mitglieder von Typen im interface ohne Doku. Die Rekursion steigt nur in
// verschachtelte Typdeklarationen ab (Tiefe wie die Schachtelung der Typen im Quelltext, unabhängig von
// Anweisungen und Ausdrücken) und bleibt deshalb.
procedure TXmlDocCheck.CheckPublic(ANode: TSyntaxNode; APublic: Boolean);
var
  mIndex: Integer;
  mMember: TSyntaxNode;
  mVisible: Boolean;
begin
  mVisible := APublic;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    mMember := ANode[mIndex];
    case mMember.Kind of
      TSyntaxKind.Visibility:
        mVisible := APublic and (SameText(mMember.Name, 'public') or SameText(mMember.Name, 'published'));
      TSyntaxKind.TypeSection, TSyntaxKind.TypeDecl, TSyntaxKind.ClassType, TSyntaxKind.ObjectType,
      TSyntaxKind.RecordType, TSyntaxKind.InterfaceType:
        if mVisible then
        begin
          CheckPublic(mMember, True);
        end;
      TSyntaxKind.RoutineHeader, TSyntaxKind.PropertyDecl:
        if mVisible and NeedsDoc(ANode, mMember) then
        begin
          ReportUndocumented(mMember);
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;
end;

procedure TXmlDocCheck.CheckInterfaceMembers;
var
  mIndex: Integer;
  mSection: TSyntaxNode;
begin
  for mIndex := 0 to FContext.Tree.Root.ChildCount - 1 do
  begin
    mSection := FContext.Tree.Root[mIndex];
    if mSection.Kind = TSyntaxKind.InterfaceSection then
    begin
      CheckPublic(mSection, True);
    end;
  end;
end;

procedure TXmlDocCheck.Run;
var
  mBlock: TDocBlock;
begin
  CollectDeclarations(FContext.Tree.Root, FDeclarations);
  FindInterface;
  if CrefsKnown(FContext, FTokens) then
  begin
    FCrefs := TDocCrefCheck.Create(Self, FContext, FReport, TRuleDerived.Resolver(FCache, FContext),
      TRuleDerived.UnitIndex(FCache, FContext), IncludeLevel(FTokens));
  end;
  for mBlock in DocBlocks(FTokens, FLines) do
  begin
    CheckBlock(mBlock);
  end;
  if FRequirePublic then
  begin
    CheckInterfaceMembers;
  end;
end;

{ TDocCrefCheck }

constructor TDocCrefCheck.Create(AOwner: TXmlDocCheck; const AContext: TRuleContext; const AReport: IRuleReport;
  AResolver: TNameResolver; const AFromUnit: TUnitIndex; ALevel: TRuleConfidence);
begin
  inherited Create;
  FOwner := AOwner;
  FContext := AContext;
  FReport := AReport;
  FResolver := AResolver;
  FFromUnit := AFromUnit;
  FLevel := ALevel;
end;

/// <summary>Ist ASymbol ein Wurzeltyp ohne Vorfahren (TObject, IInterface oder kein Klassen-/Interfacetyp)?
/// </summary>
function IsRootType(const ASymbol: TResolvedSymbol): Boolean;
begin
  Result := (Length(ASymbol.Ancestors) = 0) and (SameText(ASymbol.Name, 'TObject') or
    SameText(ASymbol.Name, 'IInterface') or not (ASymbol.SymbolKind in [TIndexSymbolKind.ClassType,
    TIndexSymbolKind.InterfaceType]));
end;

function TDocCrefCheck.ChainKnown(const AType: TResolvedSymbol): Boolean;
var
  mCurrent, mAncestor: TResolvedSymbol;
  mSteps: Integer;
begin
  mCurrent := AType;
  for mSteps := 1 to 64 do
  begin
    if mCurrent.SymbolKind = TIndexSymbolKind.HelperType then
    begin
      Exit(False);
    end;
    if not FResolver.AncestorOf(mCurrent, mAncestor) then
    begin
      Exit(IsRootType(mCurrent));
    end;
    mCurrent := mAncestor;
  end;
  Result := False;
end;

function TDocCrefCheck.NamesUnit(const AName: string): Boolean;
var
  mPart, mPrefix: string;
  mIgnored: TUnitIndex;
begin
  mPrefix := '';
  for mPart in AName.Split(['.']) do
  begin
    if mPrefix <> '' then
    begin
      mPrefix := mPrefix + '.';
    end;
    mPrefix := mPrefix + mPart;
    if FContext.Index.FindUnit(mPrefix, mIgnored) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TDocCrefCheck.OwnerOpen(const AContainer, AName: string): Boolean;
var
  mDotted: Boolean;
  mPrefix: string;
  mOwner: TResolvedSymbol;
begin
  mDotted := Pos('.', AName) > 0;
  if mDotted then
  begin
    mPrefix := Copy(AName, 1, LastDelimiter('.', AName) - 1);
  end
  else
  begin
    mPrefix := AContainer;
  end;
  Result := (mDotted or (mPrefix <> '')) and FResolver.ResolveTypeFrom(FFromUnit, mPrefix, mOwner) and
    not ChainKnown(mOwner);
end;

function TDocCrefCheck.CrefMissing(const AContainer, AName: string): Boolean;
var
  mFound: TResolvedSymbol;
begin
  Result := not Unverifiable(AName) and not FResolver.LocateCref(FFromUnit, AContainer, AName, mFound) and
    not NamesUnit(AName) and not OwnerOpen(AContainer, AName);
end;

function TDocCrefCheck.Candidates(const AContainer, AName: string; ADot, AOffset: Integer): TArray<string>;
var
  mWanted: string;
begin
  mWanted := Copy(AName, ADot + 1, MaxInt);
  FResolver.Candidates.NameFilter :=
    function(const ACandidate: string): Boolean
    begin
      Result := Abs(Length(ACandidate) - Length(mWanted)) <= 2;
    end;
  try
    if ADot > 0 then
    begin
      Result := CandidateNames(FResolver.Candidates.MemberCandidates(FContext.Tree, FContext.RelativePath,
        Copy(AName, 1, ADot - 1).Split(['.']), AOffset));
    end
    else
    begin
      Result := CandidateNames(FResolver.Candidates.ScopeCandidates(FContext.Tree, FContext.RelativePath, AOffset));
      if AContainer <> '' then
      begin
        Result := Result + CandidateNames(FResolver.Candidates.MemberCandidates(FContext.Tree, FContext.RelativePath,
          AContainer.Split(['.']), AOffset));
      end;
    end;
  finally
    FResolver.Candidates.NameFilter := nil;
  end;
end;

function TDocCrefCheck.Replacement(const AContainer, AName: string; AOffset: Integer): string;
var
  mDot: Integer;
  mClosest: string;
begin
  // Ähnlichster Name: Mitglied hinter dem Typ bzw. ein Name im Bereich der Deklaration.
  mDot := LastDelimiter('.', AName);
  mClosest := TTextFuzzy.Closest(Copy(AName, mDot + 1, MaxInt), Candidates(AContainer, AName, mDot, AOffset));
  Result := '';
  if mClosest <> '' then
  begin
    Result := Copy(AName, 1, mDot) + mClosest;
  end;
end;

procedure TDocCrefCheck.Check(const ABlock: TDocBlock; const AElement: TDocElement; const AAttribute: TDocAttribute;
  const AContainer: string; AOffset: Integer);
var
  mPrefix, mName, mRest, mReplaced, mMessage: string;
  mFound: TResolvedSymbol;
  mFixes: TArray<TRuleFix>;
begin
  SplitCref(Trim(AAttribute.Value), mPrefix, mName, mRest);
  if not CrefMissing(AContainer, mName) then
  begin
    Exit;
  end;
  mMessage := FOwner.WithCode(ABlock, cTexts[TXmlDocText.CrefNoSymbol].Fmt([AAttribute.Value]), 'W1206');
  mFixes := nil;
  mReplaced := Replacement(AContainer, mName, AOffset);
  if (mReplaced <> '') and FResolver.LocateCref(FFromUnit, AContainer, mReplaced, mFound) then
  begin
    mMessage := mMessage + cTexts[TXmlDocText.CrefMeant].Fmt([mReplaced]);
    mFixes := [TRuleFix.Create(cTexts[TXmlDocText.SetCref].Fmt([mReplaced]),
      [TRuleEdit.Create(FOwner.XmlRange(ABlock, AAttribute.ValueStart, AAttribute.ValueStop),
      mPrefix + mReplaced + mRest)])];
  end;
  FReport.Add(FOwner.XmlRange(ABlock, AElement.Start, AElement.OpenStop), mMessage, FLevel, mFixes);
end;

{ TDocSignatureCheck }

constructor TDocSignatureCheck.Create(AOwner: TXmlDocCheck; const AReport: IRuleReport; const ABlock: TDocBlock;
  AHeader: TSyntaxNode; ACheckReturns, ARequirePublic: Boolean);
begin
  inherited Create;
  FOwner := AOwner;
  FReport := AReport;
  FBlock := ABlock;
  FHeader := AHeader;
  FCheckReturns := ACheckReturns;
  FRequirePublic := ARequirePublic;
  FSignature := SignatureOf(AHeader);
  FPrevious := -1;
  FInserts := TDictionary<Integer, string>.Create;
end;

destructor TDocSignatureCheck.Destroy;
begin
  FInserts.Free;
  inherited;
end;

procedure TDocSignatureCheck.AddParam(const AElement: TDocElement; const AName: string);
begin
  FParams := FParams + [AElement];
  FParamNames := FParamNames + [AName];
  if not Contains(FSignature.Params, AName) then
  begin
    FUnknown := FUnknown + [High(FParams)];
  end;
end;

procedure TDocSignatureCheck.Collect(const AElements: TArray<TDocElement>);
var
  mElement: TDocElement;
  mAttribute: TDocAttribute;
begin
  for mElement in AElements do
  begin
    if SameText(mElement.Name, 'inheritdoc') then
    begin
      FInherits := True;
    end;
    if mElement.Depth > 0 then
    begin
      Continue;
    end;
    if SameText(mElement.Name, 'returns') then
    begin
      FHasReturns := True;
      FReturns := mElement;
    end
    else if SameText(mElement.Name, 'param') and mElement.Attribute('name', mAttribute) then
    begin
      AddParam(mElement, Trim(mAttribute.Value));
    end;
  end;
end;

procedure TDocSignatureCheck.FindMissing;
var
  mName: string;
begin
  FMissing := nil;
  if (Length(FParams) = 0) or FInherits then
  begin
    Exit;
  end;
  for mName in FSignature.Params do
  begin
    if not Contains(FParamNames, mName) then
    begin
      FMissing := FMissing + [mName];
    end;
  end;
end;

function TDocSignatureCheck.Mismatched: Boolean;
begin
  Result := (Length(FUnknown) > 0) or (Length(FMissing) > 0) or FStrayReturns or FMissingReturns;
end;

function TDocSignatureCheck.MessageText: string;
var
  mParts, mNames: TArray<string>;
  mPosition: Integer;
begin
  mParts := nil;
  if Length(FUnknown) > 0 then
  begin
    mNames := nil;
    for mPosition in FUnknown do
    begin
      mNames := mNames + [Format('<param name="%s">', [FParamNames[mPosition]])];
    end;
    mParts := mParts + [FOwner.WithCode(FBlock, cTexts[TXmlDocText.DoesNotExist].Fmt([Joined(mNames)]), 'W1207')];
  end;
  if Length(FMissing) = 1 then
  begin
    mParts := mParts + [FOwner.WithCode(FBlock, cTexts[TXmlDocText.NotDescribed].Fmt([FMissing[0]]), 'W1208')];
  end
  else if Length(FMissing) > 1 then
  begin
    mParts := mParts + [FOwner.WithCode(FBlock, cTexts[TXmlDocText.NotDescribedMany].Fmt([Joined(FMissing)]), 'W1208')];
  end;
  if FStrayReturns then
  begin
    mParts := mParts + [cTexts[TXmlDocText.ReturnsNoResult].Text];
  end;
  if FMissingReturns then
  begin
    mParts := mParts + [cTexts[TXmlDocText.ReturnsMissing].Text];
  end;
  Result := String.Join('; ', mParts) + '.';
end;

function TDocSignatureCheck.UnknownPosition(AIndex: Integer): Integer;
var
  mRow: Integer;
begin
  Result := -1;
  for mRow := 0 to High(FUnknown) do
  begin
    if FUnknown[mRow] = AIndex then
    begin
      Result := mRow;
    end;
  end;
end;

procedure TDocSignatureCheck.KeepParam(AIndex, APosition: Integer);
var
  mName: string;
  mAttribute: TDocAttribute;
  mRow: Integer;
begin
  mName := FParamNames[AIndex];
  if APosition >= 0 then
  begin
    mName := FMissing[APosition];
    FParams[AIndex].Attribute('name', mAttribute);
    FEdits := FEdits + [TRuleEdit.Create(FOwner.XmlRange(FBlock, mAttribute.ValueStart, mAttribute.ValueStop),
      mName)];
  end;
  FPrevious := FBlock.RowOf(FParams[AIndex].Stop - 1);
  for mRow := 0 to High(FSignature.Params) do
  begin
    if SameText(FSignature.Params[mRow], mName) and (FFirstRows[mRow] < 0) then
    begin
      FFirstRows[mRow] := FBlock.RowOf(FParams[AIndex].Start);
      FLastRows[mRow] := FPrevious;
    end;
  end;
end;

procedure TDocSignatureCheck.RenameParams;
var
  mIndex, mPosition: Integer;
begin
  // Korrektur: unbekannte der Reihe nach auf die fehlenden umbenennen, übrige unbekannte entfernen.
  SetLength(FFirstRows, Length(FSignature.Params));
  SetLength(FLastRows, Length(FSignature.Params));
  for mIndex := 0 to High(FSignature.Params) do
  begin
    FFirstRows[mIndex] := -1;
    FLastRows[mIndex] := -1;
  end;
  for mIndex := 0 to High(FParams) do
  begin
    mPosition := UnknownPosition(mIndex);
    if mPosition >= Length(FMissing) then
    begin
      FEdits := FEdits + [FOwner.RemoveEdit(FBlock, FParams[mIndex])];
    end
    else
    begin
      KeepParam(mIndex, mPosition);
    end;
  end;
end;

function TDocSignatureCheck.TailRow: Integer;
begin
  if FPrevious >= 0 then
  begin
    Result := FBlock.Lines[FPrevious] + 1;
  end
  else
  begin
    Result := FBlock.Lines[High(FBlock.Lines)] + 1;
  end;
end;

function TDocSignatureCheck.InsertRow(AIndex: Integer): Integer;
var
  mPosition: Integer;
begin
  Result := -1;
  for mPosition := AIndex - 1 downto 0 do
  begin
    if (Result < 0) and (FLastRows[mPosition] >= 0) then
    begin
      Result := FBlock.Lines[FLastRows[mPosition]] + 1;
    end;
  end;
  for mPosition := AIndex + 1 to High(FSignature.Params) do
  begin
    if (Result < 0) and (FFirstRows[mPosition] >= 0) then
    begin
      Result := FBlock.Lines[FFirstRows[mPosition]];
    end;
  end;
  if Result < 0 then
  begin
    Result := TailRow;
  end;
end;

procedure TDocSignatureCheck.Insert(ARow: Integer; const AText: string);
begin
  if FInserts.ContainsKey(ARow) then
  begin
    FInserts[ARow] := FInserts[ARow] + FOwner.DocLine(FBlock, AText);
  end
  else
  begin
    FInserts.Add(ARow, FOwner.DocLine(FBlock, AText));
  end;
end;

procedure TDocSignatureCheck.InsertMissing;
var
  mIndex, mRow: Integer;
  mKeys: TArray<Integer>;
begin
  // Fehlende ohne umbenanntes Gegenstück als leere Zeilen in Signaturreihenfolge.
  for mIndex := 0 to High(FSignature.Params) do
  begin
    if FFirstRows[mIndex] < 0 then
    begin
      Insert(InsertRow(mIndex), Format('<param name="%s"></param>', [FSignature.Params[mIndex]]));
    end;
  end;
  if FMissingReturns then
  begin
    Insert(TailRow, '<returns></returns>');
  end;
  mKeys := FInserts.Keys.ToArray;
  TArray.Sort<Integer>(mKeys);
  for mRow in mKeys do
  begin
    FEdits := FEdits + [TRuleEdit.Create(TTextRange.Create(mRow, 0, mRow, 0), FInserts[mRow])];
  end;
end;

function TDocSignatureCheck.ReportRange: TTextRange;
begin
  if Length(FUnknown) > 0 then
  begin
    Result := FOwner.XmlRange(FBlock, FParams[FUnknown[0]].Start, FParams[FUnknown[0]].OpenStop);
  end
  else if FStrayReturns then
  begin
    Result := FOwner.XmlRange(FBlock, FReturns.Start, FReturns.OpenStop);
  end
  else
  begin
    Result := FOwner.DeclarationRange(FHeader);
  end;
end;

procedure TDocSignatureCheck.Run(const AElements: TArray<TDocElement>);
var
  mMessage: string;
begin
  Collect(AElements);
  FindMissing;
  FStrayReturns := FCheckReturns and FHasReturns and not FSignature.HasResult;
  // Fehlendes <returns> nur, wenn vollständige Doku verlangt ist: Die korrigierte Form aus #979 beschreibt
  // die Parameter einer Funktion ohne <returns> und gilt als passend.
  FMissingReturns := FCheckReturns and FRequirePublic and FSignature.HasResult and not FHasReturns and not FInherits;
  if not Mismatched then
  begin
    Exit;
  end;
  mMessage := MessageText;
  RenameParams;
  InsertMissing;
  if FStrayReturns then
  begin
    FEdits := FEdits + [FOwner.RemoveEdit(FBlock, FReturns)];
  end;
  FReport.Add(ReportRange, mMessage, [TRuleFix.Create(cTexts[TXmlDocText.MatchSignature].Text, Sorted(FEdits))]);
end;

{ TXmlDocMismatchRule }

function TXmlDocMismatchRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cXmlDocMismatchRuleId, TRuleSeverity.Hint,
    cTexts[TXmlDocText.Title].Text);
end;

procedure TXmlDocMismatchRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TXmlDocCheck;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mCheck := TXmlDocCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

procedure RegisterXmlDocRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TXmlDocMismatchRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.XmlDoc', cTexts);

end.
