unit Atlas.Common.Lsp.ChangeSignature;

// „Signatur ändern“ (#100): Parameter hinzufügen, entfernen, umsortieren und
// umbenennen samt aller Aufrufer, Überschreibungen in Vor- und Nachfahren,
// Interface-Deklarationen und -Implementierungen sowie Ereignistypen von
// Handlern, die eine Formulardatei bindet.
//
// Ablauf: Die Code-Aktion „Signatur ändern …“ trägt den Client-Befehl
// atlas.changeSignature. Das Plugin fragt atlas.server.changeSignature.prepare
// (Parameter, Einschränkungen), zeigt die Eingabemaske und schickt das
// Ergebnis an atlas.server.changeSignature; die Antwort ist ein WorkspaceEdit
// mit Warnungen für die Vorschau.
//
// Neue Parameter: Im Modus overload bekommt die Methode die neue Signatur und
// die alte bleibt als Überladung, die mit dem angegebenen Wert weiterreicht;
// Aufrufer bleiben unverändert. Im Modus updateCallers übergibt jeder Aufrufer
// den Wert. Interface-Methoden und gebundene Handler gehen nur mit
// updateCallers. Atlas erzeugt keine Standardwerte.
//
// Abbruch: Ereignistyp aus einer Bibliothek, entfernter Parameter im Rumpf
// verwendet, Kollision mit einer vorhandenen Überladung, Deklaration
// schreibgeschützt oder außerhalb des Projekts, Zugriffsmethode einer
// Property, Ergebnis parst nicht. Warnung: Verwendung als Methodenzeiger,
// Aufrufer in schreibgeschützten Dateien (bleiben unverändert).

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Lsp.Rename,
  Atlas.Common.Lsp.ChangeSignature.Collector;

type
  {$SCOPEDENUMS ON}
  TNewParameterMode = (Overload, UpdateCallers);
  {$SCOPEDENUMS OFF}

  /// <summary>Wo „Signatur ändern“ ansetzt: Auflöser, Index, Baum, Datei, Position, Projektdateien, Lesen,
  /// Abbruch.</summary>
  TChangeSignatureSource = TSignatureSource;

  /// <summary>True, wenn die Datei schreibgeschützt ist.</summary>
  TChangeSignatureReadOnly = reference to function(const AFileName: string): Boolean;

  TChangeSignatureInfo = record
    Name: string;
    Container: string;
    /// <summary>procedure, function, constructor oder destructor.</summary>
    Keyword: string;
    ResultType: string;
    Parameters: TArray<TSignatureParameter>;
    /// <summary>Deklarationen und Rümpfe, die sich mitändern (Vorfahren, Nachfahren, Interfaces).</summary>
    Members: Integer;
    /// <summary>Gehört zu einer Interface-Methode: neue Parameter nur mit updateCallers.</summary>
    InterfaceMethod: Boolean;
    /// <summary>Ereignistyp, an den eine Formulardatei die Methode bindet; '' ohne.</summary>
    BoundEvent: string;
    /// <summary>Der Ereignistyp stammt aus einer Bibliothek: Parameter nur umbenennen.</summary>
    EventFixed: Boolean;
    Warnings: TArray<string>;
  end;

  TChangeSignatureRequest = record
    Changes: TArray<TParameterChange>;
    Mode: TNewParameterMode;
    VirtualOverload: Boolean;
  end;

  TChangeSignatureOutcome = record
    Edits: TArray<TRenameEdit>;
    Warnings: TArray<string>;
    /// <summary>Tatsächlicher Modus (overload kann zu updateCallers werden).</summary>
    Mode: TNewParameterMode;
  end;

  /// <summary>Kopf einer Routine aus TLspChangeSignature.Family: Name und Parameternamen mit Position.</summary>
  TRoutineFamilyHeader = record
    FileName: string;
    NamePos: TTextPosition;
    /// <summary>Kopf eines Rumpfs (auch eine Routine nur im implementation-Teil).</summary>
    IsBody: Boolean;
    Parameters: TArray<TSignatureParameter>;
    /// <summary>Position des Namens je Parameter, parallel zu Parameters; Line -1, wenn nicht gefunden.</summary>
    ParameterPos: TArray<TTextPosition>;
  end;

  TRoutineFamilyCall = record
    FileName: string;
    NamePos: TTextPosition;
  end;

  /// <summary>Eine Routine mit Vorfahren, Nachfahren und Interface-Deklarationen und ihren Aufrufen.</summary>
  TRoutineFamily = record
    Name: string;
    Headers: TArray<TRoutineFamilyHeader>;
    Calls: TArray<TRoutineFamilyCall>;
    /// <summary>Verwendungen als Zugriffsmethode einer Property ("Datei, Zeile n").</summary>
    Accessors: TArray<string>;
    /// <summary>Verwendungen als Methodenzeiger.</summary>
    Warnings: TArray<string>;
    /// <summary>Ereignistyp, an den eine Formulardatei die Methode bindet; '' ohne.</summary>
    BoundEvent: string;
  end;

  TLspChangeSignature = class
  public const
    ClientCommand = 'atlas.changeSignature';
    PrepareCommand = 'atlas.server.changeSignature.prepare';
    ApplyCommand = 'atlas.server.changeSignature';
    Title = 'Signatur ändern …';
  public
    /// <summary>Steht an APosition der Name einer Routine (Deklaration, Rumpf oder Aufruf)?</summary>
    class function IsOffered(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition): Boolean; static;
    /// <summary>Code-Aktion mit dem Client-Befehl. Der Aufrufer übernimmt das Objekt.</summary>
    class function ActionJson(const AUri: string; const APosition: TTextPosition): TJSONObject; static;
    /// <summary>Die Code-Aktion an APosition, wenn eingeschaltet (refactoring.changeSignature) und dort eine
    /// Routine steht; sonst nil. Der Aufrufer übernimmt die Objekte.</summary>
    class function Actions(AEnabled: Boolean; AResolver: TNameResolver; ATree: TSyntaxTree;
      const AFileName, AUri: string; const APosition: TTextPosition): TArray<TJSONObject>; static;
    /// <summary>Parameter und Einschränkungen; EJsonRpcError, wenn die Signatur nicht änderbar ist.</summary>
    class function Prepare(const ASource: TChangeSignatureSource): TChangeSignatureInfo; static;
    /// <summary>Alle Änderungen; EJsonRpcError in den Abbruchfällen.</summary>
    class function Execute(const ASource: TChangeSignatureSource; const ARequest: TChangeSignatureRequest;
      const AIsReadOnly: TChangeSignatureReadOnly): TChangeSignatureOutcome; static;
    /// <summary>Köpfe und Aufrufe der Routine an APosition samt Überschreibungen und Interfaces (für „Boolean
    /// umkehren“, #715); EJsonRpcError, wenn dort keine Routine des Projekts steht.</summary>
    class function Family(const ASource: TChangeSignatureSource): TRoutineFamily; static;
    /// <summary>Antwort auf PrepareCommand. Der Aufrufer übernimmt das Objekt.</summary>
    class function InfoToJson(const AInfo: TChangeSignatureInfo; AMode: TNewParameterMode;
      AVirtualOverload: Boolean): TJSONObject; static;
    /// <summary>Drittes Argument von ApplyCommand: {"parameters": [...], "newParameter", "virtualOverload"}.</summary>
    class function ReadRequest(const AValue: TJSONValue; ADefaultMode: TNewParameterMode;
      ADefaultVirtual: Boolean): TChangeSignatureRequest; static;
    /// <summary>{"edit": WorkspaceEdit, "warnings": [...], "newParameter": ...}. Der Aufrufer übernimmt das Objekt.</summary>
    class function OutcomeToJson(const AOutcome: TChangeSignatureOutcome): TJSONObject; static;
    class function ModeName(AMode: TNewParameterMode): string; static;
    class function ModeOf(const AName: string; ADefault: TNewParameterMode): TNewParameterMode; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Editing.ClassCompletion,
  Atlas.Text.Lines;

type
  {$SCOPEDENUMS ON}
  TEditKind = (Header, Rename, Call, Insert);
  {$SCOPEDENUMS OFF}

  TFileEdit = record
    Kind: TEditKind;
    Range: TTextRange;
    NewText: string;
    /// <summary>Bei Call: Position des Namens und die Werte für neue Parameter.</summary>
    NamePos: TTextPosition;
    Values: TArray<string>;
  end;

  TEditList = TDictionary<string, TArray<TFileEdit>>;

  /// <summary>Baut aus den gesammelten Mitgliedern und Aufrufen die Änderungen je Datei.</summary>
  TSignatureEditor = class
  private
    FCollector: TSignatureCollector;
    FRequest: TChangeSignatureRequest;
    FRoot: TMember;
    FRootNames: TArray<string>;
    FEdits: TEditList;
    FUseOverload: Boolean;
    FOutcome: TChangeSignatureOutcome;
    function AddsParameters: Boolean;
    function ChangesTypes: Boolean;
    procedure CheckRestrictions;
    procedure CheckRemovedUnused(const AMember: TMember);
    procedure ChooseMode;
    procedure CheckCollision;
    procedure AddHeaderEdits(AUnit: TSourceFile; const AMember: TMember);
    procedure AddRenameEdits(AUnit: TSourceFile; const AMember: TMember; const AChange: TParameterChange);
    procedure AddDocRemovals(AUnit: TSourceFile; const AMember: TMember);
    procedure AddMemberEdits(const AMember: TMember);
    procedure AddOverloadDeclaration(AUnit: TSourceFile; const ALineBreak: string);
    procedure AddOverloadBody(AUnit: TSourceFile; const ALineBreak: string);
    procedure MarkOverridesOverload;
    procedure AddOverload;
    procedure AddCallEdit(const ASite: TCallSite);
    function FileOfKey(const AKey: string): string;
    procedure CheckParses(AUnit: TSourceFile; const AName: string; const AFinal: TArray<TFileEdit>);
    procedure FinishFile(const AKey: string; const AIsReadOnly: TChangeSignatureReadOnly);
  public
    constructor Create(ACollector: TSignatureCollector; const ARequest: TChangeSignatureRequest);
    destructor Destroy; override;
    function Run(const AIsReadOnly: TChangeSignatureReadOnly): TChangeSignatureOutcome;
  end;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

function Contains(const AOuter, AInner: TTextRange): Boolean;
begin
  Result := not Before(AInner.StartPos, AOuter.StartPos) and not Before(AOuter.EndPos, AInner.EndPos) and
    ((AOuter.StartPos <> AInner.StartPos) or (AOuter.EndPos <> AInner.EndPos));
end;

function Overlaps(const A, B: TTextRange): Boolean;
begin
  Result := Before(A.StartPos, B.EndPos) and Before(B.StartPos, A.EndPos);
end;

{ Bearbeitungen je Datei }

procedure AddEdit(AEdits: TEditList; const AFileName: string; const AEdit: TFileEdit);
var
  mList: TArray<TFileEdit>;
  mExisting: TFileEdit;
begin
  if not AEdits.TryGetValue(UpperCase(AFileName), mList) then
  begin
    mList := nil;
  end;
  for mExisting in mList do
  begin
    if (mExisting.Range.StartPos = AEdit.Range.StartPos) and (mExisting.Range.EndPos = AEdit.Range.EndPos) and
      (mExisting.Kind = AEdit.Kind) and (mExisting.NewText = AEdit.NewText) then
    begin
      Exit;
    end;
  end;
  AEdits.AddOrSetValue(UpperCase(AFileName), mList + [AEdit]);
end;

function MakeEdit(AKind: TEditKind; const ARange: TTextRange; const ANewText: string): TFileEdit;
begin
  Result := Default(TFileEdit);
  Result.Kind := AKind;
  Result.Range := ARange;
  Result.NewText := ANewText;
end;

/// <summary>Einfügung von ANewText direkt hinter dem Token AToken.</summary>
function InsertAfter(AUnit: TSourceFile; AToken: Integer; const ANewText: string): TFileEdit;
begin
  Result := MakeEdit(TEditKind.Insert, TTextRange.Create(AUnit.Tokens[AToken].EndPos, AUnit.Tokens[AToken].EndPos),
    ANewText);
end;

/// <summary>Ersetzt das Token AToken durch ANewText.</summary>
function ReplaceToken(AUnit: TSourceFile; AToken: Integer; const ANewText: string): TFileEdit;
begin
  Result := MakeEdit(TEditKind.Rename, TTextRange.Create(AUnit.Tokens[AToken].StartPos, AUnit.Tokens[AToken].EndPos),
    ANewText);
end;

function ToTextEdits(const AEdits: TArray<TFileEdit>): TArray<TTextEdit>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AEdits));
  for mIndex := 0 to High(AEdits) do
  begin
    Result[mIndex] := TTextEdit.Create(AEdits[mIndex].Range, AEdits[mIndex].NewText);
  end;
end;

function EditSize(const AEdit: TFileEdit): Integer;
begin
  Result := (AEdit.Range.EndPos.Line - AEdit.Range.StartPos.Line) * 100000 + AEdit.Range.EndPos.Character -
    AEdit.Range.StartPos.Character;
end;

/// <summary>Indizes von AEdits, kleinste Änderung zuerst.</summary>
function SmallestFirst(const AEdits: TArray<TFileEdit>): TArray<Integer>;
var
  mIndex, mOther, mSwap: Integer;
begin
  SetLength(Result, Length(AEdits));
  for mIndex := 0 to High(AEdits) do
  begin
    Result[mIndex] := mIndex;
  end;
  for mIndex := 0 to High(Result) - 1 do
  begin
    for mOther := mIndex + 1 to High(Result) do
    begin
      if EditSize(AEdits[Result[mOther]]) < EditSize(AEdits[Result[mIndex]]) then
      begin
        mSwap := Result[mIndex];
        Result[mIndex] := Result[mOther];
        Result[mOther] := mSwap;
      end;
    end;
  end;
end;

/// <summary>Liegt AEdits[AInner] in AEdits[AOuter], ohne in einer anderen offenen Änderung darin zu stecken?</summary>
function IsOutermostIn(const AEdits: TArray<TFileEdit>; const ADone: TArray<Boolean>; AOuter, AInner: Integer): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AEdits) do
  begin
    if (mIndex <> AInner) and (mIndex <> AOuter) and not ADone[mIndex] and
      Contains(AEdits[AOuter].Range, AEdits[mIndex].Range) and Contains(AEdits[mIndex].Range, AEdits[AInner].Range) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

/// <summary>Die äußersten offenen Änderungen in AEdits[AOuter]; deren Inneres steckt schon in ihnen.</summary>
function InnerEdits(const AEdits: TArray<TFileEdit>; const ADone: TArray<Boolean>; AOuter: Integer): TArray<TFileEdit>;
var
  mOther: Integer;
begin
  Result := nil;
  for mOther := 0 to High(AEdits) do
  begin
    if (mOther <> AOuter) and not ADone[mOther] and Contains(AEdits[AOuter].Range, AEdits[mOther].Range) and
      IsOutermostIn(AEdits, ADone, AOuter, mOther) then
    begin
      Result := Result + [AEdits[mOther]];
    end;
  end;
end;

procedure MarkContained(const AEdits: TArray<TFileEdit>; var ADone: TArray<Boolean>; AOuter: Integer);
var
  mOther: Integer;
begin
  for mOther := 0 to High(AEdits) do
  begin
    if (mOther <> AOuter) and Contains(AEdits[AOuter].Range, AEdits[mOther].Range) then
    begin
      ADone[mOther] := True;
    end;
  end;
end;

/// <summary>Bildet den Aufruf AEdit auf dem Text mit den inneren Änderungen neu.</summary>
procedure RebuildCall(const AText: string; var AEdit: TFileEdit; const AInner: TArray<TFileEdit>;
  const AOld: TArray<TSignatureParameter>; const AChanges: TArray<TParameterChange>);
var
  mModified: string;
  mTokens: TArray<TPascalToken>;
  mToken: Integer;
  mRebuilt: TTextEdit;
begin
  mModified := TChangeSignature.ApplyEdits(AText, ToTextEdits(AInner));
  mTokens := TPascalLexer.Tokenize(mModified);
  mToken := TChangeSignature.NameTokenAt(mTokens, AEdit.NamePos);
  if (mToken >= 0) and TChangeSignature.CallEdit(mModified, mTokens, mToken, AOld, AChanges, AEdit.Values,
    mRebuilt) then
  begin
    AEdit.NewText := mRebuilt.NewText;
  end;
end;

function OpenEdits(const AEdits: TArray<TFileEdit>; const ADone: TArray<Boolean>): TArray<TFileEdit>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(AEdits) do
  begin
    if not ADone[mIndex] then
    begin
      Result := Result + [AEdits[mIndex]];
    end;
  end;
end;

/// <summary>Verschachtelte Aufrufe (Foo(Foo(1))): Der äußere Aufruf wird auf dem Text mit den inneren
/// Änderungen neu gebildet, die inneren entfallen.</summary>
function ResolveNesting(const AText: string; const AEdits: TArray<TFileEdit>; const AOld: TArray<TSignatureParameter>;
  const AChanges: TArray<TParameterChange>): TArray<TFileEdit>;
var
  mDone: TArray<Boolean>;
  mInner, mEdits: TArray<TFileEdit>;
  mIndex: Integer;
begin
  mEdits := Copy(AEdits);
  SetLength(mDone, Length(mEdits));
  // Kleinste zuerst, damit innere Aufrufe fertig sind, bevor der äußere sie aufnimmt.
  for mIndex in SmallestFirst(mEdits) do
  begin
    mInner := InnerEdits(mEdits, mDone, mIndex);
    if Length(mInner) = 0 then
    begin
      Continue;
    end;
    MarkContained(mEdits, mDone, mIndex);
    if mEdits[mIndex].Kind = TEditKind.Call then
    begin
      RebuildCall(AText, mEdits[mIndex], mInner, AOld, AChanges);
    end;
  end;
  Result := OpenEdits(mEdits, mDone);
end;

/// <summary>Zeilen mit /// direkt über dem Token AStart.</summary>
function DocComments(const ATokens: TArray<TPascalToken>; AStart: Integer): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  mIndex := AStart - 1;
  while (mIndex >= 0) and (ATokens[mIndex].Kind = TPascalTokenKind.Comment) and StartsStr('///', ATokens[mIndex].Text) do
  begin
    Result := [mIndex] + Result;
    Dec(mIndex);
  end;
end;

/// <summary>Stellen im Rumpf, an denen der Parameter AName steht.</summary>
function BodyUses(AUnit: TSourceFile; const AMember: TMember; const AName: string): TArray<Integer>;
begin
  Result := nil;
  if AMember.HasBody then
  begin
    Result := TChangeSignature.Uses_(AUnit.Tokens, AMember.Body.LastToken + 1, AMember.BodyLast, AName);
  end;
end;

/// <summary>Bleibt der Parameter an Stelle AIndex der alten Liste erhalten?</summary>
function IsKept(const AChanges: TArray<TParameterChange>; AIndex: Integer): Boolean;
var
  mChange: TParameterChange;
begin
  for mChange in AChanges do
  begin
    if mChange.Origin = AIndex then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function ParameterNames(const AParameters: TArray<TSignatureParameter>): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AParameters));
  for mIndex := 0 to High(AParameters) do
  begin
    Result[mIndex] := AParameters[mIndex].Name;
  end;
end;

function ParameterTypes(const AParameters: TArray<TSignatureParameter>): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AParameters));
  for mIndex := 0 to High(AParameters) do
  begin
    Result[mIndex] := AParameters[mIndex].TypeName;
  end;
end;

/// <summary>Werte für neue Parameter eines inherited-Aufrufs: ihr Name.</summary>
function InheritedValues(const AChanges: TArray<TParameterChange>): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AChanges));
  for mIndex := 0 to High(AChanges) do
  begin
    if AChanges[mIndex].Origin < 0 then
    begin
      Result[mIndex] := AChanges[mIndex].Name;
    end;
  end;
end;

/// <summary>Ändert eine der Bearbeitungen einen Kopf (nicht nur Aufrufe)?</summary>
function HasHeaderEdit(const AEdits: TArray<TFileEdit>): Boolean;
var
  mEdit: TFileEdit;
begin
  for mEdit in AEdits do
  begin
    if mEdit.Kind in [TEditKind.Header, TEditKind.Insert, TEditKind.Rename] then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure CheckOverlaps(const AName: string; const AEdits: TArray<TFileEdit>);
var
  mIndex, mOther: Integer;
begin
  for mIndex := 0 to High(AEdits) do
  begin
    for mOther := mIndex + 1 to High(AEdits) do
    begin
      if Overlaps(AEdits[mIndex].Range, AEdits[mOther].Range) then
      begin
        raise SignatureError(Format('Die Änderungen in %s überschneiden sich (Zeile %d).', [ExtractFileName(AName),
          AEdits[mIndex].Range.StartPos.Line + 1]));
      end;
    end;
  end;
end;

/// <summary>Qualifizierter Name der Weiterleitung im implementation-Teil.</summary>
function QualifiedBodyName(const ARoot: TMember): string;
begin
  if ARoot.HasBody then
  begin
    Result := ARoot.Body.QualifiedName;
  end
  else if ARoot.Container <> '' then
  begin
    Result := ARoot.Container + '.' + ARoot.Name;
  end
  else
  begin
    Result := ARoot.Name;
  end;
end;

/// <summary>Position des Namens je Parameter zwischen den Klammern; Line -1, wenn nicht gefunden.</summary>
function ParameterPositions(const ATokens: TArray<TPascalToken>; const AHeader: TSignatureHeader): TArray<TTextPosition>;
var
  mIndex, mToken: Integer;
  mPosition: TTextPosition;
begin
  Result := nil;
  mToken := AHeader.OpenToken;
  for mIndex := 0 to High(AHeader.Parameters) do
  begin
    mPosition := TTextPosition.Create(-1, 0);
    while (mToken >= 0) and (mToken < AHeader.CloseToken) and (mToken <= High(ATokens)) do
    begin
      Inc(mToken);
      if (ATokens[mToken].Kind = TPascalTokenKind.Identifier) and
        SameText(ATokens[mToken].Text, AHeader.Parameters[mIndex].Name) then
      begin
        mPosition := ATokens[mToken].StartPos;
        Break;
      end;
    end;
    Result := Result + [mPosition];
  end;
end;

/// <summary>Kopf für TRoutineFamily; False, wenn die Datei fehlt oder der Kopf keinen Namen hat.</summary>
function FamilyHeader(AUnit: TSourceFile; const AHeader: TSignatureHeader; AIsBody: Boolean;
  out AResult: TRoutineFamilyHeader): Boolean;
begin
  AResult := Default(TRoutineFamilyHeader);
  Result := (AUnit <> nil) and (AHeader.NameToken >= 0);
  if Result then
  begin
    AResult.FileName := AUnit.FileName;
    AResult.NamePos := AUnit.Tokens[AHeader.NameToken].StartPos;
    AResult.IsBody := AIsBody;
    AResult.Parameters := AHeader.Parameters;
    // Die Namen stehen in der Reihenfolge der Parameter zwischen den Klammern.
    AResult.ParameterPos := ParameterPositions(AUnit.Tokens, AHeader);
  end;
end;

{ TSignatureEditor }

constructor TSignatureEditor.Create(ACollector: TSignatureCollector; const ARequest: TChangeSignatureRequest);
begin
  inherited Create;
  FCollector := ACollector;
  FRequest := ARequest;
  FRoot := ACollector.Root;
  FRootNames := ParameterNames(FRoot.Decl.Parameters);
  FEdits := TEditList.Create;
  FOutcome := Default(TChangeSignatureOutcome);
end;

destructor TSignatureEditor.Destroy;
begin
  FEdits.Free;
  inherited;
end;

function TSignatureEditor.AddsParameters: Boolean;
var
  mChange: TParameterChange;
begin
  for mChange in FRequest.Changes do
  begin
    if mChange.Origin < 0 then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TSignatureEditor.ChangesTypes: Boolean;
var
  mIndex: Integer;
begin
  Result := Length(FRequest.Changes) <> Length(FRoot.Decl.Parameters);
  for mIndex := 0 to High(FRequest.Changes) do
  begin
    if FRequest.Changes[mIndex].Origin <> mIndex then
    begin
      Result := True;
    end;
  end;
end;

procedure TSignatureEditor.CheckRestrictions;
var
  mError: string;
begin
  mError := TChangeSignature.Validate(FRoot.Decl.Parameters, FRequest.Changes);
  if (mError = '') and ChangesTypes then
  begin
    if FCollector.EventFixed then
    begin
      mError := Format('Die Methode ist in einer Formulardatei an %s gebunden; der Ereignistyp stammt nicht aus ' +
        'dem Projekt. Die Parameter lassen sich nur umbenennen.', [FCollector.BoundEvent]);
    end
    else if Length(FCollector.Accessors) > 0 then
    begin
      mError := Format('Die Methode ist Zugriffsmethode einer Property (%s); die Parameter lassen sich nur ' +
        'umbenennen.', [FCollector.Accessors[0]]);
    end;
  end;
  if mError <> '' then
  begin
    raise SignatureError(mError);
  end;
end;

procedure TSignatureEditor.CheckRemovedUnused(const AMember: TMember);
var
  mUnit: TSourceFile;
  mIndex: Integer;
  mFound: TArray<Integer>;
begin
  // Entfernte Parameter dürfen im Rumpf nicht mehr vorkommen.
  mUnit := FCollector.Source(AMember.FileName);
  for mIndex := 0 to High(AMember.Decl.Parameters) do
  begin
    if IsKept(FRequest.Changes, mIndex) then
    begin
      Continue;
    end;
    mFound := BodyUses(mUnit, AMember, AMember.Decl.Parameters[mIndex].Name);
    if Length(mFound) > 0 then
    begin
      raise SignatureError(Format('Der Parameter "%s" wird in %s, Zeile %d noch verwendet; erst die Verwendung ' +
        'entfernen.', [AMember.Decl.Parameters[mIndex].Name, ExtractFileName(AMember.FileName),
        mUnit.Tokens[mFound[0]].StartPos.Line + 1]));
    end;
  end;
end;

procedure TSignatureEditor.ChooseMode;
begin
  FUseOverload := AddsParameters and (FRequest.Mode = TNewParameterMode.Overload);
  if FUseOverload and (FCollector.InterfaceMethod or (FCollector.BoundEvent <> '')) then
  begin
    FUseOverload := False;
    FCollector.Warnings := FCollector.Warnings + ['Interface-Methoden und gebundene Handler: Eine Überladung ' +
      'erfüllt das Interface bzw. den Ereignistyp nicht; alle Aufrufer übergeben den neuen Wert.'];
  end;
  FOutcome.Mode := TNewParameterMode.UpdateCallers;
  if FUseOverload then
  begin
    FOutcome.Mode := TNewParameterMode.Overload;
  end;
end;

procedure TSignatureEditor.CheckCollision;
var
  mNewTypes: TArray<string>;
  mSymbol: TIndexSymbol;
begin
  // Kollision mit einer vorhandenen Überladung.
  mNewTypes := ParameterTypes(TChangeSignature.NewParameters(FRoot.Decl.Parameters, FRequest.Changes, FRootNames,
    True));
  for mSymbol in FCollector.Source(FRoot.FileName).Symbols do
  begin
    if (mSymbol.Kind in SignatureRoutineKinds) and SameText(mSymbol.Container, FRoot.Container) and
      SameText(mSymbol.Name, FRoot.Name) and SameParamTypes(mSymbol.ParamTypes, mNewTypes) and
      not SameParamTypes(mSymbol.ParamTypes, FRoot.Decl.ParamTypes) then
    begin
      raise SignatureError(Format('Die neue Signatur kollidiert mit einer vorhandenen Überladung von %s (Zeile %d).',
        [FRoot.Name, mSymbol.SelectionRange.StartPos.Line + 1]));
    end;
  end;
end;

procedure TSignatureEditor.AddHeaderEdits(AUnit: TSourceFile; const AMember: TMember);
var
  mText: string;
  mEdit: TFileEdit;
begin
  mText := TChangeSignature.ParameterList(TChangeSignature.NewParameters(AMember.Decl.Parameters, FRequest.Changes,
    FRootNames, True), True);
  mEdit := MakeEdit(TEditKind.Header, TChangeSignature.HeaderEdit(AUnit.Tokens, AMember.Decl, mText).Range, mText);
  if mText <> TChangeSignature.ParameterList(AMember.Decl.Parameters, True) then
  begin
    AddEdit(FEdits, AMember.FileName, mEdit);
  end;
  if not AMember.HasBody or AMember.DeclIsBody then
  begin
    Exit;
  end;
  mText := TChangeSignature.ParameterList(TChangeSignature.NewParameters(AMember.Decl.Parameters, FRequest.Changes,
    FRootNames, False), False);
  mEdit := MakeEdit(TEditKind.Header, TChangeSignature.HeaderEdit(AUnit.Tokens, AMember.Body, mText).Range, mText);
  if ((AMember.Body.OpenToken < 0) or (mText <> TChangeSignature.ParameterList(AMember.Body.Parameters, False))) and
    ((mText <> '') or (AMember.Body.OpenToken >= 0)) then
  begin
    AddEdit(FEdits, AMember.FileName, mEdit);
  end;
end;

procedure TSignatureEditor.AddRenameEdits(AUnit: TSourceFile; const AMember: TMember; const AChange: TParameterChange);
var
  mOldName, mNewName, mComment: string;
  mToken: Integer;
begin
  mOldName := AMember.Decl.Parameters[AChange.Origin].Name;
  mNewName := TChangeSignature.NewParameters(AMember.Decl.Parameters, [AChange], FRootNames, False)[0].Name;
  if SameStr(mOldName, mNewName) then
  begin
    Exit;
  end;
  for mToken in BodyUses(AUnit, AMember, mOldName) do
  begin
    AddEdit(FEdits, AMember.FileName, ReplaceToken(AUnit, mToken, mNewName));
  end;
  // <param name="Alt"> in den ///-Zeilen über der Deklaration.
  for mToken in DocComments(AUnit.Tokens, AMember.Decl.StartToken) do
  begin
    mComment := AUnit.Tokens[mToken].Text;
    if ContainsText(mComment, 'name="' + mOldName + '"') then
    begin
      AddEdit(FEdits, AMember.FileName, ReplaceToken(AUnit, mToken, StringReplace(mComment, 'name="' + mOldName +
        '"', 'name="' + mNewName + '"', [rfIgnoreCase])));
    end;
  end;
end;

procedure TSignatureEditor.AddDocRemovals(AUnit: TSourceFile; const AMember: TMember);
var
  mIndex, mToken, mLine: Integer;
  mComment: string;
begin
  // Doku entfernter Parameter: einzeilige <param>-Zeilen löschen.
  for mIndex := 0 to High(AMember.Decl.Parameters) do
  begin
    if IsKept(FRequest.Changes, mIndex) then
    begin
      Continue;
    end;
    for mToken in DocComments(AUnit.Tokens, AMember.Decl.StartToken) do
    begin
      mComment := AUnit.Tokens[mToken].Text;
      if ContainsText(mComment, '<param name="' + AMember.Decl.Parameters[mIndex].Name + '"') and
        ContainsText(mComment, '</param>') then
      begin
        mLine := AUnit.Tokens[mToken].StartPos.Line;
        AddEdit(FEdits, AMember.FileName, MakeEdit(TEditKind.Rename, TTextRange.Create(mLine, 0, mLine + 1, 0), ''));
      end;
    end;
  end;
end;

procedure TSignatureEditor.AddMemberEdits(const AMember: TMember);
var
  mUnit: TSourceFile;
  mChange: TParameterChange;
begin
  // Köpfe, Umbenennungen im Rumpf, Doku-Kommentare.
  mUnit := FCollector.Source(AMember.FileName);
  AddHeaderEdits(mUnit, AMember);
  for mChange in FRequest.Changes do
  begin
    if (mChange.Origin >= 0) and (mChange.Origin <= High(AMember.Decl.Parameters)) then
    begin
      AddRenameEdits(mUnit, AMember, mChange);
    end;
  end;
  AddDocRemovals(mUnit, AMember);
end;

procedure TSignatureEditor.AddOverloadDeclaration(AUnit: TSourceFile; const ALineBreak: string);
var
  mText, mIndent: string;
  mVirtual: Boolean;
begin
  mVirtual := FRequest.VirtualOverload and (FRoot.Decl.HasDirective('virtual') or
    FRoot.Decl.HasDirective('dynamic') or FRoot.Decl.HasDirective('abstract'));
  mIndent := TTextLines.IndentOf(AUnit.Text, AUnit.Tokens[FRoot.Decl.StartToken].StartPos.Line);
  mText := '';
  if not FRoot.DeclIsBody then
  begin
    mText := ALineBreak + mIndent + TChangeSignature.HeaderText(FRoot.Decl, FRoot.Name, FRoot.Decl.Parameters, True) +
      TChangeSignature.OverloadDirectives(FRoot.Decl, mVirtual);
  end;
  // Ohne weitere Direktiven fallen beide Einfügungen auf dieselbe Stelle: ein Edit, feste Reihenfolge.
  if not FRoot.Decl.HasDirective('overload') then
  begin
    if FRoot.Decl.LastToken = FRoot.Decl.EndToken then
    begin
      mText := ' overload;' + mText;
    end
    else
    begin
      AddEdit(FEdits, FRoot.FileName, InsertAfter(AUnit, FRoot.Decl.EndToken, ' overload;'));
    end;
  end;
  if mText <> '' then
  begin
    AddEdit(FEdits, FRoot.FileName, InsertAfter(AUnit, FRoot.Decl.LastToken, mText));
  end;
end;

procedure TSignatureEditor.AddOverloadBody(AUnit: TSourceFile; const ALineBreak: string);
var
  mBody: string;
  mRebuilt: TTextEdit;
begin
  mBody := TChangeSignature.HeaderText(FRoot.Decl, QualifiedBodyName(FRoot), FRoot.Decl.Parameters, False);
  if FRoot.DeclIsBody then
  begin
    mBody := mBody + TChangeSignature.OverloadDirectives(FRoot.Decl, False);
  end;
  mBody := mBody + ALineBreak + 'begin' + ALineBreak + '  ' + TChangeSignature.ForwardCall(FRoot.Decl,
    FRoot.Decl.Parameters, FRequest.Changes) + ALineBreak + 'end;';
  if FRoot.HasBody then
  begin
    AddEdit(FEdits, FRoot.FileName, InsertAfter(AUnit, FRoot.BodyLast, ALineBreak + ALineBreak + mBody));
  end
  else if TClassCompletion.BodyEdit(AUnit.Tree, AUnit.Text, FRoot.Container, mBody, mRebuilt) then
  begin
    AddEdit(FEdits, FRoot.FileName, MakeEdit(TEditKind.Insert, mRebuilt.Range, mRebuilt.NewText));
  end
  else
  begin
    raise SignatureError(Format('Für die Überladung von %s fehlt ein Platz im implementation-Teil.', [FRoot.Name]));
  end;
end;

procedure TSignatureEditor.MarkOverridesOverload;
var
  mMember: TMember;
begin
  // Überschreibungen bekommen overload, sonst verdecken sie die alte Überladung des Vorfahren.
  for mMember in FCollector.Members do
  begin
    if not mMember.IsRoot and (mMember.Kind = TMemberKind.Method) and not mMember.Decl.HasDirective('overload') then
    begin
      AddEdit(FEdits, mMember.FileName, InsertAfter(FCollector.Source(mMember.FileName), mMember.Decl.EndToken,
        ' overload;'));
    end;
  end;
end;

procedure TSignatureEditor.AddOverload;
var
  mUnit: TSourceFile;
  mLineBreak: string;
begin
  // Alte Signatur als Überladung, die weiterreicht.
  mUnit := FCollector.Source(FRoot.FileName);
  mLineBreak := TTextLines.LineBreakOf(mUnit.Text);
  AddOverloadDeclaration(mUnit, mLineBreak);
  AddOverloadBody(mUnit, mLineBreak);
  MarkOverridesOverload;
end;

procedure TSignatureEditor.AddCallEdit(const ASite: TCallSite);
var
  mUnit: TSourceFile;
  mValues: TArray<string>;
  mRebuilt: TTextEdit;
  mEdit: TFileEdit;
begin
  mUnit := FCollector.Source(ASite.FileName);
  mValues := nil;
  if ASite.InheritedInMember then
  begin
    mValues := InheritedValues(FRequest.Changes);
  end;
  if TChangeSignature.CallEdit(mUnit.Text, mUnit.Tokens, TChangeSignature.NameTokenAt(mUnit.Tokens, ASite.NamePos),
    FRoot.Decl.Parameters, FRequest.Changes, mValues, mRebuilt) then
  begin
    mEdit := MakeEdit(TEditKind.Call, mRebuilt.Range, mRebuilt.NewText);
    mEdit.NamePos := ASite.NamePos;
    mEdit.Values := mValues;
    AddEdit(FEdits, ASite.FileName, mEdit);
  end;
end;

function TSignatureEditor.FileOfKey(const AKey: string): string;
var
  mMember: TMember;
  mSite: TCallSite;
begin
  Result := '';
  for mMember in FCollector.Members do
  begin
    if SameText(UpperCase(mMember.FileName), AKey) then
    begin
      Result := mMember.FileName;
    end;
  end;
  for mSite in FCollector.Calls do
  begin
    if (Result = '') and SameText(UpperCase(mSite.FileName), AKey) then
    begin
      Result := mSite.FileName;
    end;
  end;
end;

procedure TSignatureEditor.CheckParses(AUnit: TSourceFile; const AName: string; const AFinal: TArray<TFileEdit>);
var
  mTree: TSyntaxTree;
  mDiagnostic: TSyntaxDiagnostic;
begin
  if AUnit.Tree = nil then
  begin
    Exit;
  end;
  mTree := TSyntaxTreeCache.Parse(TChangeSignature.ApplyEdits(AUnit.Text, ToTextEdits(AFinal)));
  try
    if Length(mTree.Diagnostics) > Length(AUnit.Tree.Diagnostics) then
    begin
      mDiagnostic := mTree.Diagnostics[0];
      raise SignatureError(Format('Nach der Änderung parst %s nicht mehr fehlerfrei (Zeile %d: %s).',
        [ExtractFileName(AName), mDiagnostic.StartPos.Line + 1, mDiagnostic.Message]));
    end;
  finally
    mTree.Free;
  end;
end;

procedure TSignatureEditor.FinishFile(const AKey: string; const AIsReadOnly: TChangeSignatureReadOnly);
var
  mName: string;
  mUnit: TSourceFile;
  mFinal: TArray<TFileEdit>;
  mEdit: TFileEdit;
  mRenameEdit: TRenameEdit;
begin
  // Verschachtelung auflösen, Schreibschutz, Ergebnis parsen.
  mName := FileOfKey(AKey);
  mUnit := FCollector.Source(mName);
  mFinal := ResolveNesting(mUnit.Text, FEdits[AKey], FRoot.Decl.Parameters, FRequest.Changes);
  CheckOverlaps(mName, mFinal);
  if not FCollector.InProject(mName) or (Assigned(AIsReadOnly) and AIsReadOnly(mName)) then
  begin
    if HasHeaderEdit(mFinal) then
    begin
      raise SignatureError(Format('%s ist schreibgeschützt bzw. nicht im Projekt; dort steht eine Deklaration der ' +
        'Methode.', [ExtractFileName(mName)]));
    end;
    FOutcome.Warnings := FOutcome.Warnings + [Format('%s ist schreibgeschützt bzw. nicht im Projekt; %d Aufrufe ' +
      'dort bleiben unverändert.', [ExtractFileName(mName), Length(mFinal)])];
    Exit;
  end;
  CheckParses(mUnit, mName, mFinal);
  for mEdit in mFinal do
  begin
    mRenameEdit.FileName := mName;
    mRenameEdit.Range := mEdit.Range;
    mRenameEdit.NewText := mEdit.NewText;
    FOutcome.Edits := FOutcome.Edits + [mRenameEdit];
  end;
end;

function TSignatureEditor.Run(const AIsReadOnly: TChangeSignatureReadOnly): TChangeSignatureOutcome;
var
  mMember: TMember;
  mSite: TCallSite;
  mKey: string;
begin
  CheckRestrictions;
  for mMember in FCollector.Members do
  begin
    CheckRemovedUnused(mMember);
  end;
  ChooseMode;
  CheckCollision;
  for mMember in FCollector.Members do
  begin
    AddMemberEdits(mMember);
  end;
  if FUseOverload then
  begin
    AddOverload;
  end;
  // Aufrufer: im Modus overload nur inherited-Aufrufe in den Rümpfen (sonst riefe die Überschreibung sich
  // über die alte Überladung selbst auf).
  for mSite in FCollector.Calls do
  begin
    if mSite.InheritedInMember or not FUseOverload then
    begin
      AddCallEdit(mSite);
    end;
  end;
  for mKey in FEdits.Keys.ToArray do
  begin
    if Length(FEdits[mKey]) > 0 then
    begin
      FinishFile(mKey, AIsReadOnly);
    end;
  end;
  FOutcome.Warnings := FCollector.Warnings + FOutcome.Warnings;
  Result := FOutcome;
end;

{ TLspChangeSignature }

class function TLspChangeSignature.ModeName(AMode: TNewParameterMode): string;
begin
  if AMode = TNewParameterMode.UpdateCallers then
  begin
    Result := 'updateCallers';
  end
  else
  begin
    Result := 'overload';
  end;
end;

class function TLspChangeSignature.ModeOf(const AName: string; ADefault: TNewParameterMode): TNewParameterMode;
begin
  if SameText(AName, 'updateCallers') then
  begin
    Result := TNewParameterMode.UpdateCallers;
  end
  else if SameText(AName, 'overload') then
  begin
    Result := TNewParameterMode.Overload;
  end
  else
  begin
    Result := ADefault;
  end;
end;

class function TLspChangeSignature.IsOffered(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): Boolean;
var
  mToken: Integer;
  mHeader: TSignatureHeader;
  mResolved: TResolvedSymbol;
  mText: string;
begin
  Result := False;
  if (ATree = nil) or (AResolver = nil) then
  begin
    Exit;
  end;
  mToken := TChangeSignature.NameTokenAt(ATree.Tokens, APosition);
  if mToken < 0 then
  begin
    Exit;
  end;
  // Kopf einer Routine: ohne Namensauflösung. Den Text braucht ReadHeader nur für die Parameter.
  mText := '';
  if TChangeSignature.ReadHeader(mText, ATree.Tokens, mToken, mHeader) then
  begin
    Exit(True);
  end;
  mResolved := AResolver.Resolve(ATree, AFileName, APosition);
  Result := (mResolved.Kind = TResolvedKind.Symbol) and (mResolved.SymbolKind in SignatureRoutineKinds);
end;

class function TLspChangeSignature.ActionJson(const AUri: string; const APosition: TTextPosition): TJSONObject;
var
  Command: TJSONObject;
  Arguments: TJSONArray;
begin
  Arguments := TJSONArray.Create;
  Arguments.Add(AUri);
  Arguments.AddElement(TLspPositions.PositionToJson(APosition));
  Command := TJSONObject.Create;
  Command.AddPair('title', Title);
  Command.AddPair('command', ClientCommand);
  Command.AddPair('arguments', Arguments);
  Result := TJSONObject.Create;
  Result.AddPair('title', Title);
  Result.AddPair('kind', 'refactor.rewrite');
  Result.AddPair('command', Command);
end;

class function TLspChangeSignature.Actions(AEnabled: Boolean; AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName, AUri: string; const APosition: TTextPosition): TArray<TJSONObject>;
begin
  Result := nil;
  if AEnabled and IsOffered(AResolver, ATree, AFileName, APosition) then
  begin
    Result := [ActionJson(AUri, APosition)];
  end;
end;
class function TLspChangeSignature.Prepare(const ASource: TChangeSignatureSource): TChangeSignatureInfo;
var
  mCollector: TSignatureCollector;
  mRoot: TMember;
begin
  Result := Default(TChangeSignatureInfo);
  mCollector := TSignatureCollector.Create(ASource);
  try
    mCollector.Collect;
    mRoot := mCollector.Root;
    Result.Name := mRoot.Name;
    Result.Container := mRoot.Container;
    Result.Keyword := mRoot.Decl.Keyword;
    Result.ResultType := mRoot.Decl.ResultType;
    Result.Parameters := mRoot.Decl.Parameters;
    Result.Members := Length(mCollector.Members);
    Result.InterfaceMethod := mCollector.InterfaceMethod;
    Result.BoundEvent := mCollector.BoundEvent;
    Result.EventFixed := mCollector.EventFixed;
    Result.Warnings := mCollector.Warnings;
    if Length(mCollector.Accessors) > 0 then
    begin
      Result.Warnings := Result.Warnings + [Format('Zugriffsmethode einer Property (%s): Parameter lassen sich nur ' +
        'umbenennen.', [mCollector.Accessors[0]])];
    end;
  finally
    mCollector.Free;
  end;
end;

class function TLspChangeSignature.Family(const ASource: TChangeSignatureSource): TRoutineFamily;
var
  mCollector: TSignatureCollector;
  mMember: TMember;
  mSite: TCallSite;
  mCall: TRoutineFamilyCall;
  mHeader: TRoutineFamilyHeader;
begin
  Result := Default(TRoutineFamily);
  mCollector := TSignatureCollector.Create(ASource);
  try
    mCollector.Collect;
    Result.Name := mCollector.Root.Name;
    for mMember in mCollector.Members do
    begin
      if mMember.Kind = TMemberKind.EventType then
      begin
        Continue;
      end;
      if FamilyHeader(mCollector.Source(mMember.FileName), mMember.Decl, mMember.DeclIsBody, mHeader) then
      begin
        Result.Headers := Result.Headers + [mHeader];
      end;
      if mMember.HasBody and not mMember.DeclIsBody and FamilyHeader(mCollector.Source(mMember.FileName),
        mMember.Body, True, mHeader) then
      begin
        Result.Headers := Result.Headers + [mHeader];
      end;
    end;
    for mSite in mCollector.Calls do
    begin
      mCall.FileName := mSite.FileName;
      mCall.NamePos := mSite.NamePos;
      Result.Calls := Result.Calls + [mCall];
    end;
    Result.Accessors := mCollector.Accessors;
    Result.Warnings := mCollector.Warnings;
    Result.BoundEvent := mCollector.BoundEvent;
  finally
    mCollector.Free;
  end;
end;

class function TLspChangeSignature.Execute(const ASource: TChangeSignatureSource;
  const ARequest: TChangeSignatureRequest; const AIsReadOnly: TChangeSignatureReadOnly): TChangeSignatureOutcome;
var
  mCollector: TSignatureCollector;
  mEditor: TSignatureEditor;
begin
  mCollector := TSignatureCollector.Create(ASource);
  try
    mCollector.Collect;
    mEditor := TSignatureEditor.Create(mCollector, ARequest);
    try
      Result := mEditor.Run(AIsReadOnly);
    finally
      mEditor.Free;
    end;
  finally
    mCollector.Free;
  end;
end;

class function TLspChangeSignature.InfoToJson(const AInfo: TChangeSignatureInfo; AMode: TNewParameterMode;
  AVirtualOverload: Boolean): TJSONObject;
var
  Parameters, Warnings: TJSONArray;
  Parameter: TSignatureParameter;
  Item: TJSONObject;
  Warning: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', AInfo.Name);
  Result.AddPair('container', AInfo.Container);
  Result.AddPair('kind', AInfo.Keyword);
  Result.AddPair('resultType', AInfo.ResultType);
  Parameters := TJSONArray.Create;
  Result.AddPair('parameters', Parameters);
  for Parameter in AInfo.Parameters do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('name', Parameter.Name);
    Item.AddPair('type', Parameter.TypeName);
    Item.AddPair('modifier', Parameter.Modifier);
    Item.AddPair('default', Parameter.DefaultValue);
    Parameters.AddElement(Item);
  end;
  Result.AddPair('members', TJSONNumber.Create(AInfo.Members));
  Result.AddPair('interfaceMethod', TJSONBool.Create(AInfo.InterfaceMethod));
  Result.AddPair('boundEvent', AInfo.BoundEvent);
  Result.AddPair('eventFixed', TJSONBool.Create(AInfo.EventFixed));
  // Neue Parameter: Interface und gebundene Handler nur mit updateCallers.
  Result.AddPair('overloadPossible', TJSONBool.Create(not AInfo.InterfaceMethod and (AInfo.BoundEvent = '')));
  Result.AddPair('newParameter', ModeName(AMode));
  Result.AddPair('virtualOverload', TJSONBool.Create(AVirtualOverload));
  Warnings := TJSONArray.Create;
  Result.AddPair('warnings', Warnings);
  for Warning in AInfo.Warnings do
  begin
    Warnings.Add(Warning);
  end;
end;

class function TLspChangeSignature.ReadRequest(const AValue: TJSONValue; ADefaultMode: TNewParameterMode;
  ADefaultVirtual: Boolean): TChangeSignatureRequest;
var
  Item: TJSONValue;
  Items: TJSONArray;
  Change: TParameterChange;
  Text: string;
  Flag: Boolean;
begin
  Result := Default(TChangeSignatureRequest);
  Result.Mode := ADefaultMode;
  Result.VirtualOverload := ADefaultVirtual;
  if not (AValue is TJSONObject) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Die neue Signatur fehlt.');
  end;
  if TJSONObject(AValue).TryGetValue<string>('newParameter', Text) then
  begin
    Result.Mode := ModeOf(Text, ADefaultMode);
  end;
  // TryGetValue setzt den Ausgabewert unter Delphi auch ohne Feld zurück: nur bei Erfolg übernehmen.
  if TJSONObject(AValue).TryGetValue<Boolean>('virtualOverload', Flag) then
  begin
    Result.VirtualOverload := Flag;
  end;
  Items := TJSONObject(AValue).GetValue('parameters') as TJSONArray;
  if Items = nil then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Feld "parameters" fehlt.');
  end;
  for Item in Items do
  begin
    if not (Item is TJSONObject) then
    begin
      Continue;
    end;
    Change := Default(TParameterChange);
    Change.Origin := TJSONObject(Item).GetValue<Integer>('origin', -1);
    Change.Name := Trim(TJSONObject(Item).GetValue<string>('name', ''));
    Change.TypeName := Trim(TJSONObject(Item).GetValue<string>('type', ''));
    Change.Modifier := Trim(TJSONObject(Item).GetValue<string>('modifier', ''));
    Change.Value := Trim(TJSONObject(Item).GetValue<string>('value', ''));
    Result.Changes := Result.Changes + [Change];
  end;
end;

class function TLspChangeSignature.OutcomeToJson(const AOutcome: TChangeSignatureOutcome): TJSONObject;
var
  Changes, Edit: TJSONObject;
  List, Warnings: TJSONArray;
  Item: TJSONObject;
  Change: TRenameEdit;
  Uri, Warning: string;
begin
  Changes := TJSONObject.Create;
  for Change in AOutcome.Edits do
  begin
    Uri := TDocumentUris.FromPath(Change.FileName);
    List := Changes.GetValue(Uri) as TJSONArray;
    if List = nil then
    begin
      List := TJSONArray.Create;
      Changes.AddPair(Uri, List);
    end;
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(Change.Range));
    Item.AddPair('newText', Change.NewText);
    List.AddElement(Item);
  end;
  Edit := TJSONObject.Create;
  Edit.AddPair('changes', Changes);
  Result := TJSONObject.Create;
  Result.AddPair('edit', Edit);
  Warnings := TJSONArray.Create;
  Result.AddPair('warnings', Warnings);
  for Warning in AOutcome.Warnings do
  begin
    Warnings.Add(Warning);
  end;
  Result.AddPair('newParameter', ModeName(AOutcome.Mode));
end;

end.
