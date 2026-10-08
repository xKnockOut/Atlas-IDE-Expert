unit BDLsp.Common.Editing.SlashCommands;

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
// Eingetragen sind /uses (#254) und die Deklarationsbefehle (#294).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Pascal.Contract,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Projects.Contract,
  BDLsp.Common.Rules.Contract;

type
  /// <summary>Zugriff auf Projekt und Editor für Befehle, die mehr als die Datei ändern (#301).</summary>
  ISlashHost = interface
    ['{8E4A2C61-3B7D-4F95-A0C8-5D1E9F27B364}']
    /// <summary>Geladenes Projekt zur Datei AUri; False ohne Projekt.</summary>
    function Project(const AUri: string; out AProject: TProjectInfo): Boolean;
    function ReadFile(const AFileName: string; out AText: string): Boolean;
    function DirectoryExists(const APath: string): Boolean;
    /// <summary>Schreibt die .dproj in ihrer Kodierung zurück und lädt das Projekt neu.</summary>
    procedure WriteProject(const AUri, AText: string);
    /// <summary>Wechselt Konfiguration bzw. Plattform ('' = unverändert) wie der Befehl aus #46.</summary>
    procedure SelectBuild(const AUri, AConfig, APlatform: string);
    /// <summary>Öffnet AFileName im Editor und markiert ASelection (window/showDocument).</summary>
    procedure ShowDocument(const AFileName: string; const ASelection: TTextRange);
    /// <summary>Vorlage für /header (#306): slashCommands.headerTemplate, sonst die der Regel file-header;
    /// '' ohne.</summary>
    function HeaderTemplate(const AUri: string): string;
  end;

  /// <summary>Aktionen, die erst nach erfolgreichem Befehl laufen; bei Hinweisen werden sie verworfen.</summary>
  TSlashActions = class
  private
    FItems: TList<TProc>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AAction: TProc);
    procedure Run;
  end;

  /// <summary>Ort und Inhalt der Befehlszeile.</summary>
  TSlashContext = record
    /// <summary>Ganzer Text der Datei, Befehlszeile noch enthalten.</summary>
    Text: string;
    /// <summary>Zeile des Befehls ab 0.</summary>
    Line: Integer;
    /// <summary>Ganze Befehlszeile.</summary>
    LineText: string;
    Name: string;
    /// <summary>Text nach dem Namen, ohne führende und folgende Leerzeichen.</summary>
    Arguments: string;
    Namespaces: TArray<string>;
    /// <summary>Symbolindex für Vorfahren und Interfaces aus anderen Units (#295); nil ohne.</summary>
    Index: ISymbolIndex;
    /// <summary>Eingestellte Delphi-Version (BDS-Nummer, #109); '' = unbekannt, alles erlaubt.</summary>
    DelphiVersion: string;
    /// <summary>URI der Datei; '' ohne.</summary>
    Uri: string;
    /// <summary>Projekt und Editor; nil ohne (z. B. bei der Prüfung stehen gebliebener Zeilen).</summary>
    Host: ISlashHost;
    /// <summary>Ziel für Defer; nil, wenn nichts ausgeführt werden soll.</summary>
    Actions: TSlashActions;
    /// <summary>Merkt AAction für nach dem Befehl vor; ohne Actions ohne Wirkung.</summary>
    procedure Defer(const AAction: TProc);
  end;

  /// <summary>Führt den Befehl aus. False mit AReason, wenn er hier nicht passt.</summary>
  TSlashExecute = reference to function(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>;
    out AReason: string): Boolean;

  TSlashCommand = record
    Name: string;
    Summary: string;
    Example: string;
    Execute: TSlashExecute;
  end;

  /// <summary>Schnellbefehle für AUri: False = alle aus; ADisabled = abgeschaltete Namen ohne "/".</summary>
  TSlashCommandsProvider = reference to function(const AUri: string; out ADisabled: TArray<string>): Boolean;

  /// <summary>Hinweis zu einer Befehlszeile, die stehen bleibt.</summary>
  TSlashProblem = record
    Range: TTextRange;
    Message: string;
  end;

  TSlashCommandRegistry = class
  private
    FCommands: TList<TSlashCommand>;
    FLock: TObject;
    class var FShared: TSlashCommandRegistry;
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
    function AfterEnter(const AText: string; const APosition: TTextPosition; const ANamespaces,
      ADisabled: TArray<string>; out AEdits: TArray<TRuleEdit>; const AIndex: ISymbolIndex = nil;
      const ADelphiVersion: string = ''; const AUri: string = ''; const AHost: ISlashHost = nil): Boolean;
    /// <summary>Hinweise für Befehlszeilen, die stehen geblieben sind (unbekannt, abgeschaltet, falscher Ort).</summary>
    function Problems(const AText: string; const ADisabled: TArray<string>;
      const AIndex: ISymbolIndex = nil; const ADelphiVersion: string = ''): TArray<TSlashProblem>;
    /// <summary>Befehle, deren Name mit APrefix beginnt (ohne "/"), ohne abgeschaltete.</summary>
    function Matching(const APrefix: string; const ADisabled: TArray<string>): TArray<TSlashCommand>;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Defaults,
  BDLsp.Common.Pascal.Lexer,
  BDLsp.Common.Editing.UsesCommand,
  BDLsp.Common.Editing.DeclarationCommands,
  BDLsp.Common.Editing.ClassCommands,
  BDLsp.Common.Editing.WrapCommands,
  BDLsp.Common.Editing.MaintenanceCommands,
  BDLsp.Common.Editing.TypeCommands,
  BDLsp.Common.Editing.CollectionCommands,
  BDLsp.Common.Editing.ExpressionCommands,
  BDLsp.Common.Editing.RefactoringCommands,
  BDLsp.Common.Editing.ProjectCommands,
  BDLsp.Common.Editing.DatabaseCommands,
  BDLsp.Common.Editing.DocumentationCommands,
  BDLsp.Common.Editing.ComponentCommands,
  BDLsp.Common.Editing.WinApiCommands,
  BDLsp.Common.Editing.TaskCommands,
  BDLsp.Common.Editing.RecordCommands,
  BDLsp.Common.Editing.ErrorCommands;

function IsDisabled(const AName: string; const ADisabled: TArray<string>): Boolean;
var
  Name: string;
begin
  for Name in ADisabled do
    if SameText(Name, AName) then
      Exit(True);
  Result := False;
end;

function SplitLines(const AText: string; out ALineBreak: string): TArray<string>;
begin
  if Pos(#13#10, AText) > 0 then
    ALineBreak := #13#10
  else
    ALineBreak := #10;
  Result := AText.Split([ALineBreak]);
end;

{ TSlashContext }

procedure TSlashContext.Defer(const AAction: TProc);
begin
  if Actions <> nil then
    Actions.Add(AAction);
end;

{ TSlashActions }

constructor TSlashActions.Create;
begin
  inherited Create;
  FItems := TList<TProc>.Create;
end;

destructor TSlashActions.Destroy;
begin
  FItems.Free;
  inherited;
end;

procedure TSlashActions.Add(const AAction: TProc);
begin
  FItems.Add(AAction);
end;

procedure TSlashActions.Run;
var
  Action: TProc;
begin
  for Action in FItems do
    Action();
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
begin
  FreeAndNil(FShared);
end;

function UsesCommand: TSlashCommand;
begin
  Result.Name := 'uses';
  Result.Summary := 'Units ins uses des Abschnitts eintragen';
  Result.Example := '/uses System.SysUtils, System.Classes';
  Result.Execute :=
    function(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean
    begin
      AReason := '';
      Result := TUsesCommand.AfterEnter(AContext.Text, TTextPosition.Create(AContext.Line + 1, 0),
        AContext.Namespaces, AEdits);
      if not Result then
        AReason := 'Erwartet werden Unit-Namen, z. B. /uses System.SysUtils, System.Classes';
    end;
end;

class function TSlashCommandRegistry.Shared: TSlashCommandRegistry;
var
  Created: TSlashCommandRegistry;
begin
  if FShared = nil then
  begin
    Created := TSlashCommandRegistry.Create;
    Created.Register(UsesCommand);
    RegisterDeclarationCommands(Created);
    RegisterClassCommands(Created);
    RegisterWrapCommands(Created);
    RegisterMaintenanceCommands(Created);
    RegisterTypeCommands(Created);
    RegisterCollectionCommands(Created);
    RegisterErrorCommands(Created);
    RegisterRefactoringCommands(Created);
    RegisterExpressionCommands(Created);
    RegisterProjectCommands(Created);
    RegisterDatabaseCommands(Created);
    RegisterDocumentationCommands(Created);
    RegisterComponentCommands(Created);
    RegisterWinApiCommands(Created);
    RegisterTaskCommands(Created);
    RegisterRecordCommands(Created);
    if AtomicCmpExchange(Pointer(FShared), Pointer(Created), nil) <> nil then
      Created.Free;
  end;
  Result := FShared;
end;

procedure TSlashCommandRegistry.Register(const ACommand: TSlashCommand);
var
  Existing: TSlashCommand;
begin
  if Find(ACommand.Name, Existing) then
    raise EArgumentException.CreateFmt('Schnellbefehl /%s ist schon eingetragen', [ACommand.Name]);
  TMonitor.Enter(FLock);
  try
    FCommands.Add(ACommand);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TSlashCommandRegistry.Find(const AName: string; out ACommand: TSlashCommand): Boolean;
var
  Command: TSlashCommand;
begin
  TMonitor.Enter(FLock);
  try
    for Command in FCommands do
      if SameText(Command.Name, AName) then
      begin
        ACommand := Command;
        Exit(True);
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
  Text: string;
  Index: Integer;
begin
  AName := '';
  AArguments := '';
  Text := Trim(ALine);
  // "/name": Buchstabe direkt nach "/"; "//" ist ein Kommentar.
  if (Length(Text) < 2) or (Text[1] <> '/') or not CharInSet(Text[2], ['A'..'Z', 'a'..'z']) then
    Exit(False);
  Index := 2;
  while (Index <= Length(Text)) and CharInSet(Text[Index], ['A'..'Z', 'a'..'z', '0'..'9', '_', '!', '-']) do
    Inc(Index);
  if (Index <= Length(Text)) and (Text[Index] <> ' ') then
    Exit(False);
  AName := Copy(Text, 2, Index - 2);
  AArguments := Trim(Copy(Text, Index, MaxInt));
  Result := True;
end;

class function TSlashCommandRegistry.IsCodeLine(const ATokens: TArray<TPascalToken>; ALine: Integer): Boolean;
var
  Token: TPascalToken;
  InAsm: Boolean;
begin
  InAsm := False;
  for Token in ATokens do
  begin
    if Token.StartPos.Line > ALine then
      Break;
    // Mehrzeiliger Kommentar oder String über der Zeile.
    if (Token.StartPos.Line < ALine) and (Token.EndPos.Line >= ALine) and
      (Token.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.StringLiteral]) then
      Exit(False);
    if Token.StartPos.Line < ALine then
    begin
      if Token.IsKeyword('asm') then
        InAsm := True
      else if InAsm and Token.IsKeyword('end') then
        InAsm := False;
    end;
  end;
  Result := not InAsm;
end;

function TSlashCommandRegistry.AfterEnter(const AText: string; const APosition: TTextPosition; const ANamespaces,
  ADisabled: TArray<string>; out AEdits: TArray<TRuleEdit>; const AIndex: ISymbolIndex;
  const ADelphiVersion, AUri: string; const AHost: ISlashHost): Boolean;
var
  Lines: TArray<string>;
  LineBreak, Reason: string;
  Context: TSlashContext;
  Command: TSlashCommand;
begin
  AEdits := nil;
  Context := Default(TSlashContext);
  Context.Line := APosition.Line - 1;
  Lines := SplitLines(AText, LineBreak);
  if (Context.Line < 0) or (Context.Line > High(Lines)) then
    Exit(False);
  Context.LineText := Lines[Context.Line];
  if not Split(Context.LineText, Context.Name, Context.Arguments) or IsDisabled(Context.Name, ADisabled) or
    not Find(Context.Name, Command) or not IsCodeLine(TPascalLexer.Tokenize(AText), Context.Line) then
    Exit(False);
  Context.Text := AText;
  Context.Namespaces := ANamespaces;
  Context.Index := AIndex;
  Context.DelphiVersion := ADelphiVersion;
  Context.Uri := AUri;
  Context.Host := AHost;
  Context.Actions := TSlashActions.Create;
  try
    Result := Command.Execute(Context, AEdits, Reason);
    if Result then
      Context.Actions.Run
    else
      AEdits := nil;
  finally
    Context.Actions.Free;
  end;
end;

function TSlashCommandRegistry.Problems(const AText: string; const ADisabled: TArray<string>;
  const AIndex: ISymbolIndex; const ADelphiVersion: string): TArray<TSlashProblem>;
var
  Lines: TArray<string>;
  LineBreak, Name, Arguments, Reason: string;
  Tokens: TArray<TPascalToken>;
  Line, Start: Integer;
  Command: TSlashCommand;
  Context: TSlashContext;
  Edits: TArray<TRuleEdit>;
  Problem: TSlashProblem;
begin
  Result := nil;
  Tokens := nil;
  Lines := SplitLines(AText, LineBreak);
  for Line := 0 to High(Lines) do
  begin
    if not Split(Lines[Line], Name, Arguments) then
      Continue;
    if Tokens = nil then
      Tokens := TPascalLexer.Tokenize(AText);
    if not IsCodeLine(Tokens, Line) then
      Continue;
    Reason := '';
    if not Find(Name, Command) then
      Reason := Format('Unbekannter Schnellbefehl /%s', [Name])
    else if IsDisabled(Name, ADisabled) then
      Reason := Format('Schnellbefehl /%s ist abgeschaltet (slashCommands.disabled)', [Name])
    else
    begin
      Context := Default(TSlashContext);
      Context.Text := AText;
      Context.Line := Line;
      Context.LineText := Lines[Line];
      Context.Name := Name;
      Context.Arguments := Arguments;
      Context.Index := AIndex;
      Context.DelphiVersion := ADelphiVersion;
      if not Command.Execute(Context, Edits, Reason) and (Reason = '') then
        Reason := Format('Schnellbefehl /%s passt hier nicht', [Name]);
    end;
    if Reason = '' then
      Continue;
    Start := Pos('/', Lines[Line]) - 1;
    Problem.Range := TTextRange.Create(Line, Start, Line, Length(TrimRight(Lines[Line])));
    Problem.Message := Reason;
    Result := Result + [Problem];
  end;
end;

function TSlashCommandRegistry.Matching(const APrefix: string; const ADisabled: TArray<string>): TArray<TSlashCommand>;
var
  Command: TSlashCommand;
begin
  Result := nil;
  for Command in Commands do
    if StartsText(APrefix, Command.Name) and not IsDisabled(Command.Name, ADisabled) then
      Result := Result + [Command];
end;

end.
