unit Atlas.Common.Editing.SlashCommands;

// Befehlsrahmen für Schnellbefehle mit "/" (#293), ohne Protokollbezug.
//
// Eine Zeile, die nach der Einrückung mit "/name" beginnt, ist ein
// Schnellbefehl. Nach Enter fragt der Enter-Handler das Register: Der Befehl
// liefert genau eine Liste von Änderungen (ein Rückgängig-Schritt), die
// Befehlszeile verschwindet. Unbekannte, abgeschaltete oder am falschen Ort
// stehende Befehle bleiben stehen und bekommen eine Hinweis-Diagnose; es wird
// nie stillschweigend etwas gelöscht. Zeilen in Kommentaren, Strings und
// asm-Blöcken sind keine Befehle.
//
// Eingetragen sind /uses (#254) und die Befehle der *Commands-Units. Die
// gemeinsamen Typen (TSlashContext, TSlashCommand, ISlashHost …) stehen in
// Atlas.Common.Editing.Contract; die Befehls-Units binden nur diese ein und
// melden ihre Befehle über TSlashRegister. Nur dieses Register bindet alle
// Befehls-Units ein, so entsteht kein Unit-Zyklus (#1450).
//
// Die Befehle rücken mit zwei Leerzeichen je Ebene ein; Reindent setzt die
// zusätzliche Einrückung danach in den Formatstil der Datei um (#43: Breite
// bzw. Tabulatoren aus Editor, .editorconfig und "format").
//
// Run führt eine Befehlszeile auch ohne Enter aus (Erzeugen-Menü, #719) und
// nennt den Grund, wenn sie nicht passt; WrapUntil begrenzt dabei das
// Umschließen auf eine Markierung. Erlaubte Orte, Gruppen und
// Argumentauswahl je Befehl stehen in Atlas.Common.Editing.SlashMenu.

interface

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Umgebung, in der ein Schnellbefehl läuft: Namespace-Präfixe für /uses, abgeschaltete Befehle
  /// (slashCommands.disabled), Index für Vorfahren aus anderen Units, Delphi-Version, Datei, Host (nil ohne
  /// Editor) und Formatstil für die Einrückung (#43).</summary>
  TSlashEnvironment = record
    Namespaces: TArray<string>;
    Disabled: TArray<string>;
    Index: ISymbolIndex;
    DelphiVersion: string;
    Uri: string;
    Host: ISlashHost;
    Style: TFormatStyle;
    /// <summary>Ohne Index, Delphi-Version, Datei und Host, mit dem Vorgabestil.</summary>
    class function Create(const ANamespaces, ADisabled: TArray<string>): TSlashEnvironment; overload; static;
    /// <summary>Mit dem Vorgabestil.</summary>
    class function Create(const ANamespaces, ADisabled: TArray<string>; const AIndex: ISymbolIndex;
      const ADelphiVersion, AUri: string; const AHost: ISlashHost): TSlashEnvironment; overload; static;
    /// <summary>Kopie mit dem Formatstil AStyle.</summary>
    function WithStyle(const AStyle: TFormatStyle): TSlashEnvironment;
  end;

  TSlashCommandRegistry = class
  private
    FCommands: TList<TSlashCommand>;
    FLock: TObject;
    /// <summary>Je Sprache ein Register, weil die Beschreibungen beim Eintragen übersetzt werden.</summary>
    class var FShared: array[TTextLanguage] of TSlashCommandRegistry;
  public
    constructor Create;
    destructor Destroy; override;
    class destructor DestroyShared;
    /// <summary>Register mit den eingebauten Befehlen.</summary>
    class function Shared: TSlashCommandRegistry; static;
    procedure Register(const ACommand: TSlashCommand);
    function Find(const AName: string; out ACommand: TSlashCommand): Boolean;
    /// <summary>Alle Befehle, nach Namen sortiert.</summary>
    function Commands: TArray<TSlashCommand>;
    /// <summary>Ist ALine ein Befehl "/name Argumente"? Ohne Prüfung, ob der Name bekannt ist.</summary>
    class function Split(const ALine: string; out AName, AArguments: string): Boolean; static;
    /// <summary>Steht Zeile ALine im Code (nicht in Kommentar, String oder asm)?</summary>
    class function IsCodeLine(const ATokens: TArray<TPascalToken>; ALine: Integer): Boolean; static;
    /// <summary>Edits nach Enter in APosition.Line für die Befehlszeile darüber. False, wenn dort kein
    /// ausführbarer Befehl steht (dann bleibt die Zeile stehen).</summary>
    function AfterEnter(const AText: string; const APosition: TTextPosition; const AEnvironment: TSlashEnvironment;
      out AEdits: TArray<TTextEdit>): Boolean; overload;
    /// <summary>Wie oben mit AIndex, ohne Delphi-Version, Datei und Host, im Vorgabestil.</summary>
    function AfterEnter(const AText: string; const APosition: TTextPosition; const ANamespaces,
      ADisabled: TArray<string>; out AEdits: TArray<TTextEdit>; const AIndex: ISymbolIndex): Boolean; overload;
    /// <summary>Wie oben ohne Index.</summary>
    function AfterEnter(const AText: string; const APosition: TTextPosition; const ANamespaces,
      ADisabled: TArray<string>; out AEdits: TArray<TTextEdit>): Boolean; overload;
    /// <summary>Führt die Befehlszeile ALine (ab 0) aus wie AfterEnter, aber mit Grund (#719): False mit AReason,
    /// wenn dort kein ausführbarer Befehl steht. AWrapUntil &gt; ALine begrenzt das Umschließen auf die Zeilen
    /// davor (TSlashContext.WrapUntil); 0 = bis zum Blockende.</summary>
    function Run(const AText: string; ALine, AWrapUntil: Integer; const AEnvironment: TSlashEnvironment;
      out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
    /// <summary>Einrückung der Änderungen AEdits zu AText nach AStyle (#43): Was eine Zeile über die Einrückung
    /// der Zeile hinaus trägt, an der die Änderung beginnt (dahinter oder, bei eingerückten vorhandenen Zeilen,
    /// davor), gilt als Ebenen zu zwei Leerzeichen und wird zu
    /// AStyle.IndentSize Leerzeichen bzw. einem Tabulator je Ebene. Zeilen mit anderer Einrückung, die erste
    /// Zeile einer Änderung mitten in einer Zeile und der Vorgabestil (zwei Leerzeichen) bleiben unverändert.</summary>
    class function Reindent(const AText: string; const AEdits: TArray<TTextEdit>;
      const AStyle: TFormatStyle): TArray<TTextEdit>; static;
    /// <summary>Hinweise für Befehlszeilen, die stehen geblieben sind (unbekannt, abgeschaltet, falscher
    /// Ort).</summary>
    function Problems(const AText: string; const ADisabled: TArray<string>;
      const AIndex: ISymbolIndex; const ADelphiVersion: string): TArray<TSlashProblem>; overload;
    /// <summary>Wie oben mit ADelphiVersion = ''.</summary>
    function Problems(const AText: string; const ADisabled: TArray<string>;
      const AIndex: ISymbolIndex): TArray<TSlashProblem>; overload;
    /// <summary>Wie oben ohne Index (AIndex = nil, ADelphiVersion = '').</summary>
    function Problems(const AText: string; const ADisabled: TArray<string>): TArray<TSlashProblem>; overload;
    /// <summary>Befehle, deren Name mit APrefix beginnt (ohne "/"), ohne abgeschaltete.</summary>
    function Matching(const APrefix: string; const ADisabled: TArray<string>): TArray<TSlashCommand>;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Defaults,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.UsesCommand,
  Atlas.Common.Editing.DeclarationCommands,
  Atlas.Common.Editing.ClassCommands,
  Atlas.Common.Editing.WrapCommands,
  Atlas.Common.Editing.MaintenanceCommands,
  Atlas.Common.Editing.TypeCommands,
  Atlas.Common.Editing.CollectionCommands,
  Atlas.Common.Editing.ExpressionCommands,
  Atlas.Common.Editing.RefactoringCommands,
  Atlas.Common.Editing.ProjectCommands,
  Atlas.Common.Editing.DatabaseCommands,
  Atlas.Common.Editing.DocumentationCommands,
  Atlas.Common.Editing.ComponentCommands,
  Atlas.Common.Editing.WinApiCommands,
  Atlas.Common.Editing.TaskCommands,
  Atlas.Common.Editing.RecordCommands,
  Atlas.Common.Editing.TestCommands,
  Atlas.Common.Editing.ErrorCommands,
  Atlas.Text.Lines;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TSlashCommandsText = (AddUnitsToTheUses, ExpectedAreUnitNamesE, SlashCommandIsAlreadyRegistered,
    SlashCommandIsSwitchedOff, SlashCommandsDoNotApply, SlashCommandDoesNotFit, UnknownSlashCommand);

const
  cTexts: array[TSlashCommandsText] of TAtlasText = (
    (De: 'Units ins uses des Abschnitts eintragen'; En: 'Add units to the uses of the section'),
    (De: 'Erwartet werden Unit-Namen, z. B. /uses System.SysUtils, System.Classes';
     En: 'Expected are unit names, e.g. /uses System.SysUtils, System.Classes'),
    (De: 'Schnellbefehl /%s ist schon eingetragen'; En: 'Slash command /%s is already registered'),
    (De: 'Schnellbefehl /%s ist abgeschaltet (slashCommands.disabled)';
     En: 'Slash command /%s is switched off (slashCommands.disabled)'),
    (De: 'Schnellbefehle gelten nicht in Kommentaren, Strings und asm-Blöcken';
     En: 'Slash commands do not apply in comments, strings and asm blocks'),
    (De: 'Schnellbefehl /%s passt hier nicht'; En: 'Slash command /%s does not fit here'),
    (De: 'Unbekannter Schnellbefehl /%s'; En: 'Unknown slash command /%s'));

{$SCOPEDENUMS OFF}

function IsDisabled(const AName: string; const ADisabled: TArray<string>): Boolean;
var
  mName: string;
begin
  for mName in ADisabled do
  begin
    if SameText(mName, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TSlashEnvironment }

class function TSlashEnvironment.Create(const ANamespaces, ADisabled: TArray<string>): TSlashEnvironment;
begin
  Result := Create(ANamespaces, ADisabled, nil, '', '', nil);
end;

class function TSlashEnvironment.Create(const ANamespaces, ADisabled: TArray<string>; const AIndex: ISymbolIndex;
  const ADelphiVersion, AUri: string; const AHost: ISlashHost): TSlashEnvironment;
begin
  Result.Namespaces := ANamespaces;
  Result.Disabled := ADisabled;
  Result.Index := AIndex;
  Result.DelphiVersion := ADelphiVersion;
  Result.Uri := AUri;
  Result.Host := AHost;
  Result.Style := TFormatStyle.Default;
end;

function TSlashEnvironment.WithStyle(const AStyle: TFormatStyle): TSlashEnvironment;
begin
  Result := Self;
  Result.Style := AStyle;
end;

{ TSlashCommandRegistry }

constructor TSlashCommandRegistry.Create;
begin
  inherited Create;
  FCommands := TList<TSlashCommand>.Create;
  FLock := TObject.Create;
end;

destructor TSlashCommandRegistry.Destroy;
begin
  FLock.Free;
  FCommands.Free;
  inherited;
end;

class destructor TSlashCommandRegistry.DestroyShared;
var
  mLanguage: TTextLanguage;
begin
  for mLanguage := Low(TTextLanguage) to High(TTextLanguage) do
  begin
    FreeAndNil(FShared[mLanguage]);
  end;
end;

function UsesCommand: TSlashCommand;
begin
  Result.Name := 'uses';
  Result.Summary := cTexts[TSlashCommandsText.AddUnitsToTheUses].Text;
  Result.Example := '/uses System.SysUtils, System.Classes';
  Result.Execute :=
    function(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean
    begin
      AReason := '';
      Result := TUsesCommand.AfterEnter(AContext.Text, TTextPosition.Create(AContext.Line + 1, 0),
        AContext.Namespaces, AEdits);
      if not Result then
      begin
        AReason := cTexts[TSlashCommandsText.ExpectedAreUnitNamesE].Text;
      end;
    end;
end;

/// <summary>Eintragen in ARegistry für die Register*Commands der Befehls-Units (#1450).</summary>
function RegisterInto(ARegistry: TSlashCommandRegistry): TSlashRegister;
begin
  Result :=
    procedure(const ACommand: TSlashCommand)
    begin
      ARegistry.Register(ACommand);
    end;
end;

class function TSlashCommandRegistry.Shared: TSlashCommandRegistry;
var
  mCreated: TSlashCommandRegistry;
  mRegister: TSlashRegister;
  mLanguage: TTextLanguage;
begin
  mLanguage := TAtlasLocale.Language;
  if FShared[mLanguage] = nil then
  begin
    mCreated := TSlashCommandRegistry.Create;
    mRegister := RegisterInto(mCreated);
    mCreated.Register(UsesCommand);
    RegisterDeclarationCommands(mRegister);
    RegisterClassCommands(mRegister);
    RegisterWrapCommands(mRegister);
    RegisterMaintenanceCommands(mRegister);
    RegisterTypeCommands(mRegister);
    RegisterCollectionCommands(mRegister);
    RegisterErrorCommands(mRegister);
    RegisterRefactoringCommands(mRegister);
    RegisterExpressionCommands(mRegister);
    RegisterProjectCommands(mRegister);
    RegisterDatabaseCommands(mRegister);
    RegisterDocumentationCommands(mRegister);
    RegisterComponentCommands(mRegister);
    RegisterWinApiCommands(mRegister);
    RegisterTaskCommands(mRegister);
    RegisterRecordCommands(mRegister);
    RegisterTestCommands(mRegister);
    if AtomicCmpExchange(Pointer(FShared[mLanguage]), Pointer(mCreated), nil) <> nil then
    begin
      mCreated.Free;
    end;
  end;
  Result := FShared[mLanguage];
end;

procedure TSlashCommandRegistry.Register(const ACommand: TSlashCommand);
var
  mExisting: TSlashCommand;
begin
  if Find(ACommand.Name, mExisting) then
  begin
    raise EArgumentException.CreateFmt(cTexts[TSlashCommandsText.SlashCommandIsAlreadyRegistered].Text,
      [ACommand.Name]);
  end;
  TMonitor.Enter(FLock);
  try
    FCommands.Add(ACommand);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TSlashCommandRegistry.Find(const AName: string; out ACommand: TSlashCommand): Boolean;
var
  mCommand: TSlashCommand;
begin
  TMonitor.Enter(FLock);
  try
    for mCommand in FCommands do
    begin
      if SameText(mCommand.Name, AName) then
      begin
        ACommand := mCommand;
        Exit(True);
      end;
    end;
    Result := False;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TSlashCommandRegistry.Commands: TArray<TSlashCommand>;
begin
  TMonitor.Enter(FLock);
  try
    Result := FCommands.ToArray;
  finally
    TMonitor.Exit(FLock);
  end;
  TArray.Sort<TSlashCommand>(Result, TComparer<TSlashCommand>.Construct(
    function(const ALeft, ARight: TSlashCommand): Integer
    begin
      Result := CompareText(ALeft.Name, ARight.Name);
    end));
end;

class function TSlashCommandRegistry.Split(const ALine: string; out AName, AArguments: string): Boolean;
var
  mText: string;
  mIndex: Integer;
begin
  AName := '';
  AArguments := '';
  mText := Trim(ALine);
  // "/name": Buchstabe direkt nach "/"; "//" ist ein Kommentar.
  if (Length(mText) < 2) or (mText[1] <> '/') or not CharInSet(mText[2], ['A'..'Z', 'a'..'z']) then
  begin
    Exit(False);
  end;
  mIndex := 2;
  while (mIndex <= Length(mText)) and CharInSet(mText[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '_', '!', '-']) do
  begin
    Inc(mIndex);
  end;
  if (mIndex <= Length(mText)) and (mText[mIndex] <> ' ') then
  begin
    Exit(False);
  end;
  AName := Copy(mText, 2, mIndex - 2);
  AArguments := Trim(Copy(mText, mIndex, MaxInt));
  Result := True;
end;

class function TSlashCommandRegistry.IsCodeLine(const ATokens: TArray<TPascalToken>; ALine: Integer): Boolean;
var
  mToken: TPascalToken;
  mInAsm: Boolean;
begin
  mInAsm := False;
  for mToken in ATokens do
  begin
    if mToken.StartPos.Line > ALine then
    begin
      Break;
    end;
    // Mehrzeiliger Kommentar oder String über der Zeile.
    if (mToken.StartPos.Line < ALine) and (mToken.EndPos.Line >= ALine) and
      (mToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.StringLiteral]) then
    begin
      Exit(False);
    end;
    if mToken.StartPos.Line < ALine then
    begin
      if mToken.IsKeyword('asm') then
      begin
        mInAsm := True;
      end
      else if mInAsm and mToken.IsKeyword('end') then
      begin
        mInAsm := False;
      end;
    end;
  end;
  Result := not mInAsm;
end;

function TSlashCommandRegistry.AfterEnter(const AText: string; const APosition: TTextPosition;
  const AEnvironment: TSlashEnvironment; out AEdits: TArray<TTextEdit>): Boolean;
var
  mReason: string;
begin
  Result := Run(AText, APosition.Line - 1, 0, AEnvironment, AEdits, mReason);
end;

function TSlashCommandRegistry.AfterEnter(const AText: string; const APosition: TTextPosition; const ANamespaces,
  ADisabled: TArray<string>; out AEdits: TArray<TTextEdit>; const AIndex: ISymbolIndex): Boolean;
begin
  Result := AfterEnter(AText, APosition, TSlashEnvironment.Create(ANamespaces, ADisabled, AIndex, '', '', nil),
    AEdits);
end;

function TSlashCommandRegistry.AfterEnter(const AText: string; const APosition: TTextPosition; const ANamespaces,
  ADisabled: TArray<string>; out AEdits: TArray<TTextEdit>): Boolean;
begin
  Result := AfterEnter(AText, APosition, TSlashEnvironment.Create(ANamespaces, ADisabled), AEdits);
end;

/// <summary>Führende Leerzeichen und Tabulatoren von ALine.</summary>
function Leading(const ALine: string): string;
var
  mCount: Integer;
begin
  mCount := 0;
  while (mCount < Length(ALine)) and CharInSet(ALine[mCount + 1], [' ', #9]) do
  begin
    Inc(mCount);
  end;
  Result := Copy(ALine, 1, mCount);
end;

/// <summary>Einrückung je Ebene nach AStyle: Tabulator, IndentSize Leerzeichen oder zwei.</summary>
function LevelUnitOf(const AStyle: TFormatStyle): string;
begin
  if AStyle.UseTabs then
  begin
    Result := #9;
  end
  else if AStyle.IndentSize >= 1 then
  begin
    Result := StringOfChar(' ', AStyle.IndentSize);
  end
  else
  begin
    Result := '  ';
  end;
end;

/// <summary>Zeile APart einer Änderung mit dem Zusatz zur Einrückung ABase in Ebenen zu ALevelUnit; unverändert bei
/// Leerzeilen, anderer Einrückung oder Tabulatoren im Zusatz.</summary>
function ReindentedPart(const APart, ABase, ALevelUnit: string): string;
var
  mIndent, mExtra: string;
begin
  Result := APart;
  mIndent := Leading(APart);
  if Length(mIndent) = Length(APart) then
  begin
    Exit;
  end;
  // Zusatz hinter der Einrückung der Zeile oder (eingerückte vorhandene Zeilen) davor.
  if mIndent.StartsWith(ABase) then
  begin
    mExtra := Copy(mIndent, Length(ABase) + 1, MaxInt);
  end
  else if mIndent.EndsWith(ABase) then
  begin
    mExtra := Copy(mIndent, 1, Length(mIndent) - Length(ABase));
  end;
  if (mExtra <> '') and (Pos(#9, mExtra) = 0) then
  begin
    Result := ABase + DupeString(ALevelUnit, Length(mExtra) div 2) + StringOfChar(' ', Length(mExtra) mod 2) +
      Copy(APart, Length(mIndent) + 1, MaxInt);
  end;
end;

/// <summary>AEdit mit der Einrückung nach ALevelUnit; ALines sind die Zeilen des Texts vor der Änderung.</summary>
function ReindentedEdit(const AEdit: TTextEdit; const ALines: TArray<string>; const ALevelUnit: string): TTextEdit;
var
  mBase: string;
  mParts: TArray<string>;
  mIndex: Integer;
begin
  Result := AEdit;
  mBase := '';
  if (AEdit.Range.StartPos.Line >= 0) and (AEdit.Range.StartPos.Line <= High(ALines)) then
  begin
    mBase := Leading(ALines[AEdit.Range.StartPos.Line]);
  end;
  mParts := AEdit.NewText.Split([#10]);
  for mIndex := 0 to High(mParts) do
  begin
    // Erste Zeile mitten in einer Zeile: dort gibt es keine Einrückung.
    if (mIndex > 0) or (AEdit.Range.StartPos.Character <= 0) then
    begin
      mParts[mIndex] := ReindentedPart(mParts[mIndex], mBase, ALevelUnit);
    end;
  end;
  Result.NewText := string.Join(#10, mParts);
end;

class function TSlashCommandRegistry.Reindent(const AText: string; const AEdits: TArray<TTextEdit>;
  const AStyle: TFormatStyle): TArray<TTextEdit>;
var
  mLines: TArray<string>;
  mLevelUnit: string;
  mIndex: Integer;
begin
  Result := Copy(AEdits);
  mLevelUnit := LevelUnitOf(AStyle);
  if mLevelUnit = '  ' then
  begin
    Exit;
  end;
  mLines := TTextLines.SplitLines(AText);
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex] := ReindentedEdit(Result[mIndex], mLines, mLevelUnit);
  end;
end;

/// <summary>Kontext mit Zeile, Name und Argumenten der Befehlszeile ALine von AText; False ohne Befehlszeile.
/// </summary>
function CommandContext(const AText: string; ALine: Integer; out AContext: TSlashContext): Boolean;
var
  mLines: TArray<string>;
  mLineBreak: string;
begin
  AContext := Default(TSlashContext);
  AContext.Line := ALine;
  mLines := TTextLines.SplitLines(AText, mLineBreak);
  Result := (ALine >= 0) and (ALine <= High(mLines));
  if Result then
  begin
    AContext.LineText := mLines[ALine];
    Result := TSlashCommandRegistry.Split(AContext.LineText, AContext.Name, AContext.Arguments);
  end;
end;

/// <summary>Grund, wenn der Befehl AName in ARegistry fehlt oder abgeschaltet ist; sonst '' und ACommand.</summary>
function KnownIssue(ARegistry: TSlashCommandRegistry; const AName: string; const ADisabled: TArray<string>;
  out ACommand: TSlashCommand): string;
begin
  Result := '';
  if not ARegistry.Find(AName, ACommand) then
  begin
    Result := cTexts[TSlashCommandsText.UnknownSlashCommand].Fmt([AName]);
  end
  else if IsDisabled(AName, ADisabled) then
  begin
    Result := cTexts[TSlashCommandsText.SlashCommandIsSwitchedOff].Fmt([AName]);
  end;
end;

/// <summary>Grund, warum der Befehl aus AContext nicht laufen darf: unbekannt, abgeschaltet oder nicht im Code;
/// sonst '' und ACommand.</summary>
function CommandIssue(ARegistry: TSlashCommandRegistry; const AText: string; const AContext: TSlashContext;
  const ADisabled: TArray<string>; out ACommand: TSlashCommand): string;
begin
  Result := KnownIssue(ARegistry, AContext.Name, ADisabled, ACommand);
  if (Result = '') and not TSlashCommandRegistry.IsCodeLine(TPascalLexer.Tokenize(AText), AContext.Line) then
  begin
    Result := cTexts[TSlashCommandsText.SlashCommandsDoNotApply].Text;
  end;
end;

/// <summary>Führt ACommand in AContext aus, rückt die Änderungen nach AContext.Style ein und erledigt danach die
/// vorgemerkten Aktionen. False mit AReason, wenn der Befehl nicht passt.</summary>
function ExecuteCommand(const ACommand: TSlashCommand; var AContext: TSlashContext; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  mAction: TProc;
begin
  AReason := '';
  AContext.Actions := TList<TProc>.Create;
  try
    Result := ACommand.Execute(AContext, AEdits, AReason);
    if Result then
    begin
      AEdits := TSlashCommandRegistry.Reindent(AContext.Text, AEdits, AContext.Style);
      for mAction in AContext.Actions do
      begin
        mAction();
      end;
    end
    else
    begin
      AEdits := nil;
      if AReason = '' then
      begin
        AReason := cTexts[TSlashCommandsText.SlashCommandDoesNotFit].Fmt([AContext.Name]);
      end;
    end;
  finally
    AContext.Actions.Free;
    AContext.Actions := nil;
  end;
end;

function TSlashCommandRegistry.Run(const AText: string; ALine, AWrapUntil: Integer;
  const AEnvironment: TSlashEnvironment; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mContext: TSlashContext;
  mCommand: TSlashCommand;
begin
  AEdits := nil;
  AReason := '';
  if not CommandContext(AText, ALine, mContext) then
  begin
    Exit(False);
  end;
  AReason := CommandIssue(Self, AText, mContext, AEnvironment.Disabled, mCommand);
  if AReason <> '' then
  begin
    Exit(False);
  end;
  mContext.WrapUntil := AWrapUntil;
  mContext.Text := AText;
  mContext.Namespaces := AEnvironment.Namespaces;
  mContext.Index := AEnvironment.Index;
  mContext.DelphiVersion := AEnvironment.DelphiVersion;
  mContext.Style := AEnvironment.Style;
  mContext.Uri := AEnvironment.Uri;
  mContext.Host := AEnvironment.Host;
  Result := ExecuteCommand(mCommand, mContext, AEdits, AReason);
end;

function TSlashCommandRegistry.Problems(const AText: string; const ADisabled: TArray<string>;
  const AIndex: ISymbolIndex): TArray<TSlashProblem>;
begin
  Result := Problems(AText, ADisabled, AIndex, '');
end;

function TSlashCommandRegistry.Problems(const AText: string; const ADisabled: TArray<string>): TArray<TSlashProblem>;
begin
  Result := Problems(AText, ADisabled, nil, '');
end;

/// <summary>Grund, warum die stehen gebliebene Befehlszeile aus AContext nicht läuft; '' wenn sie liefe.</summary>
function ProblemReason(ARegistry: TSlashCommandRegistry; const AContext: TSlashContext;
  const ADisabled: TArray<string>): string;
var
  mCommand: TSlashCommand;
  mEdits: TArray<TTextEdit>;
begin
  Result := KnownIssue(ARegistry, AContext.Name, ADisabled, mCommand);
  if (Result = '') and not mCommand.Execute(AContext, mEdits, Result) and (Result = '') then
  begin
    Result := cTexts[TSlashCommandsText.SlashCommandDoesNotFit].Fmt([AContext.Name]);
  end;
end;

/// <summary>Hinweis AReason über dem Befehl in der Zeile ALine mit dem Text ALineText.</summary>
function LineProblem(const ALineText: string; ALine: Integer; const AReason: string): TSlashProblem;
begin
  Result.Range := TTextRange.Create(ALine, Pos('/', ALineText) - 1, ALine, Length(TrimRight(ALineText)));
  Result.Message := AReason;
end;

function TSlashCommandRegistry.Problems(const AText: string; const ADisabled: TArray<string>;
  const AIndex: ISymbolIndex; const ADelphiVersion: string): TArray<TSlashProblem>;
var
  mLines: TArray<string>;
  mLineBreak, mReason: string;
  mTokens: TArray<TPascalToken>;
  mLine: Integer;
  mContext: TSlashContext;
begin
  Result := nil;
  mTokens := nil;
  mLines := TTextLines.SplitLines(AText, mLineBreak);
  for mLine := 0 to High(mLines) do
  begin
    mContext := Default(TSlashContext);
    if not Split(mLines[mLine], mContext.Name, mContext.Arguments) then
    begin
      Continue;
    end;
    if mTokens = nil then
    begin
      mTokens := TPascalLexer.Tokenize(AText);
    end;
    if not IsCodeLine(mTokens, mLine) then
    begin
      Continue;
    end;
    mContext.Text := AText;
    mContext.Line := mLine;
    mContext.LineText := mLines[mLine];
    mContext.Index := AIndex;
    mContext.DelphiVersion := ADelphiVersion;
    mReason := ProblemReason(Self, mContext, ADisabled);
    if mReason <> '' then
    begin
      Result := Result + [LineProblem(mLines[mLine], mLine, mReason)];
    end;
  end;
end;

function TSlashCommandRegistry.Matching(const APrefix: string; const ADisabled: TArray<string>): TArray<TSlashCommand>;
var
  mCommand: TSlashCommand;
begin
  Result := nil;
  for mCommand in Commands do
  begin
    if StartsText(APrefix, mCommand.Name) and not IsDisabled(mCommand.Name, ADisabled) then
    begin
      Result := Result + [mCommand];
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.SlashCommands', cTexts);

end.
