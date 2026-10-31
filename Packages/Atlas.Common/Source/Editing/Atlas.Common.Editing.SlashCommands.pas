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
  Atlas.Common.Editing.Contract;

type
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
      ADisabled: TArray<string>; out AEdits: TArray<TTextEdit>; const AIndex: ISymbolIndex = nil;
      const ADelphiVersion: string = ''; const AUri: string = ''; const AHost: ISlashHost = nil): Boolean; overload;
    /// <summary>Wie AfterEnter, mit der Einrückung nach AStyle (#43).</summary>
    function AfterEnter(const AText: string; const APosition: TTextPosition; const ANamespaces,
      ADisabled: TArray<string>; const AIndex: ISymbolIndex; const ADelphiVersion, AUri: string;
      const AHost: ISlashHost; const AStyle: TFormatStyle; out AEdits: TArray<TTextEdit>): Boolean; overload;
    /// <summary>Führt die Befehlszeile ALine (ab 0) aus wie AfterEnter, aber mit Grund (#719): False mit AReason,
    /// wenn dort kein ausführbarer Befehl steht. AWrapUntil &gt; ALine begrenzt das Umschließen auf die Zeilen
    /// davor (TSlashContext.WrapUntil); 0 = bis zum Blockende.</summary>
    function Run(const AText: string; ALine, AWrapUntil: Integer; const ANamespaces, ADisabled: TArray<string>;
      const AIndex: ISymbolIndex; const ADelphiVersion, AUri: string; const AHost: ISlashHost;
      out AEdits: TArray<TTextEdit>; out AReason: string): Boolean; overload;
    /// <summary>Wie Run, mit der Einrückung nach AStyle (#43).</summary>
    function Run(const AText: string; ALine, AWrapUntil: Integer; const ANamespaces, ADisabled: TArray<string>;
      const AIndex: ISymbolIndex; const ADelphiVersion, AUri: string; const AHost: ISlashHost;
      const AStyle: TFormatStyle; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean; overload;
    /// <summary>Einrückung der Änderungen AEdits zu AText nach AStyle (#43): Was eine Zeile über die Einrückung
    /// der Zeile hinaus trägt, an der die Änderung beginnt (dahinter oder, bei eingerückten vorhandenen Zeilen,
    /// davor), gilt als Ebenen zu zwei Leerzeichen und wird zu
    /// AStyle.IndentSize Leerzeichen bzw. einem Tabulator je Ebene. Zeilen mit anderer Einrückung, die erste
    /// Zeile einer Änderung mitten in einer Zeile und der Vorgabestil (zwei Leerzeichen) bleiben unverändert.</summary>
    class function Reindent(const AText: string; const AEdits: TArray<TTextEdit>;
      const AStyle: TFormatStyle): TArray<TTextEdit>; static;
    /// <summary>Hinweise für Befehlszeilen, die stehen geblieben sind (unbekannt, abgeschaltet, falscher Ort).</summary>
    function Problems(const AText: string; const ADisabled: TArray<string>;
      const AIndex: ISymbolIndex = nil; const ADelphiVersion: string = ''): TArray<TSlashProblem>;
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
  Atlas.Common.Editing.ErrorCommands,
  Atlas.Text.Lines;

function IsDisabled(const AName: string; const ADisabled: TArray<string>): Boolean;
var
  Name: string;
begin
  for Name in ADisabled do
    if SameText(Name, AName) then
      Exit(True);
  Result := False;
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
    function(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean
    begin
      AReason := '';
      Result := TUsesCommand.AfterEnter(AContext.Text, TTextPosition.Create(AContext.Line + 1, 0),
        AContext.Namespaces, AEdits);
      if not Result then
        AReason := 'Erwartet werden Unit-Namen, z. B. /uses System.SysUtils, System.Classes';
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
  Created: TSlashCommandRegistry;
  mRegister: TSlashRegister;
begin
  if FShared = nil then
  begin
    Created := TSlashCommandRegistry.Create;
    mRegister := RegisterInto(Created);
    Created.Register(UsesCommand);
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
  ADisabled: TArray<string>; out AEdits: TArray<TTextEdit>; const AIndex: ISymbolIndex;
  const ADelphiVersion, AUri: string; const AHost: ISlashHost): Boolean;
begin
  Result := AfterEnter(AText, APosition, ANamespaces, ADisabled, AIndex, ADelphiVersion, AUri, AHost,
    TFormatStyle.Default, AEdits);
end;

function TSlashCommandRegistry.AfterEnter(const AText: string; const APosition: TTextPosition; const ANamespaces,
  ADisabled: TArray<string>; const AIndex: ISymbolIndex; const ADelphiVersion, AUri: string;
  const AHost: ISlashHost; const AStyle: TFormatStyle; out AEdits: TArray<TTextEdit>): Boolean;
var
  Reason: string;
begin
  Result := Run(AText, APosition.Line - 1, 0, ANamespaces, ADisabled, AIndex, ADelphiVersion, AUri, AHost, AStyle,
    AEdits, Reason);
end;

function TSlashCommandRegistry.Run(const AText: string; ALine, AWrapUntil: Integer; const ANamespaces,
  ADisabled: TArray<string>; const AIndex: ISymbolIndex; const ADelphiVersion, AUri: string;
  const AHost: ISlashHost; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
begin
  Result := Run(AText, ALine, AWrapUntil, ANamespaces, ADisabled, AIndex, ADelphiVersion, AUri, AHost,
    TFormatStyle.Default, AEdits, AReason);
end;

class function TSlashCommandRegistry.Reindent(const AText: string; const AEdits: TArray<TTextEdit>;
  const AStyle: TFormatStyle): TArray<TTextEdit>;

  function Leading(const ALine: string): string;
  var
    Count: Integer;
  begin
    Count := 0;
    while (Count < Length(ALine)) and CharInSet(ALine[Count + 1], [' ', #9]) do
      Inc(Count);
    Result := Copy(ALine, 1, Count);
  end;

var
  Lines, Parts: TArray<string>;
  LevelUnit, Base, Part, Indent, Extra: string;
  Index, PartIndex, Levels, Rest: Integer;
  Edit: TTextEdit;
begin
  Result := Copy(AEdits);
  if AStyle.UseTabs then
    LevelUnit := #9
  else if AStyle.IndentSize >= 1 then
    LevelUnit := StringOfChar(' ', AStyle.IndentSize)
  else
    LevelUnit := '  ';
  if LevelUnit = '  ' then
    Exit;
  Lines := TTextLines.SplitLines(AText);
  for Index := 0 to High(Result) do
  begin
    Edit := Result[Index];
    Base := '';
    if (Edit.Range.StartPos.Line >= 0) and (Edit.Range.StartPos.Line <= High(Lines)) then
      Base := Leading(Lines[Edit.Range.StartPos.Line]);
    Parts := Edit.NewText.Split([#10]);
    for PartIndex := 0 to High(Parts) do
    begin
      // Erste Zeile mitten in einer Zeile: dort gibt es keine Einrückung.
      if (PartIndex = 0) and (Edit.Range.StartPos.Character > 0) then
        Continue;
      Part := Parts[PartIndex];
      Indent := Leading(Part);
      if Length(Indent) = Length(Part) then
        Continue;
      // Zusatz hinter der Einrückung der Zeile oder (eingerückte vorhandene Zeilen) davor.
      if Indent.StartsWith(Base) then
        Extra := Copy(Indent, Length(Base) + 1, MaxInt)
      else if Indent.EndsWith(Base) then
        Extra := Copy(Indent, 1, Length(Indent) - Length(Base))
      else
        Continue;
      if (Extra = '') or (Pos(#9, Extra) > 0) then
        Continue;
      Levels := Length(Extra) div 2;
      Rest := Length(Extra) mod 2;
      Extra := '';
      while Levels > 0 do
      begin
        Extra := Extra + LevelUnit;
        Dec(Levels);
      end;
      Extra := Extra + StringOfChar(' ', Rest);
      Parts[PartIndex] := Base + Extra + Copy(Part, Length(Indent) + 1, MaxInt);
    end;
    Edit.NewText := string.Join(#10, Parts);
    Result[Index] := Edit;
  end;
end;

function TSlashCommandRegistry.Run(const AText: string; ALine, AWrapUntil: Integer; const ANamespaces,
  ADisabled: TArray<string>; const AIndex: ISymbolIndex; const ADelphiVersion, AUri: string;
  const AHost: ISlashHost; const AStyle: TFormatStyle; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  Lines: TArray<string>;
  LineBreak: string;
  Context: TSlashContext;
  Command: TSlashCommand;
  Action: TProc;
begin
  AEdits := nil;
  AReason := '';
  Context := Default(TSlashContext);
  Context.Line := ALine;
  Lines := TTextLines.SplitLines(AText, LineBreak);
  if (Context.Line < 0) or (Context.Line > High(Lines)) then
    Exit(False);
  Context.LineText := Lines[Context.Line];
  if not Split(Context.LineText, Context.Name, Context.Arguments) then
    Exit(False);
  if not Find(Context.Name, Command) then
  begin
    AReason := Format('Unbekannter Schnellbefehl /%s', [Context.Name]);
    Exit(False);
  end;
  if IsDisabled(Context.Name, ADisabled) then
  begin
    AReason := Format('Schnellbefehl /%s ist abgeschaltet (slashCommands.disabled)', [Context.Name]);
    Exit(False);
  end;
  if not IsCodeLine(TPascalLexer.Tokenize(AText), Context.Line) then
  begin
    AReason := 'Schnellbefehle gelten nicht in Kommentaren, Strings und asm-Blöcken';
    Exit(False);
  end;
  Context.WrapUntil := AWrapUntil;
  Context.Text := AText;
  Context.Namespaces := ANamespaces;
  Context.Index := AIndex;
  Context.DelphiVersion := ADelphiVersion;
  Context.Style := AStyle;
  Context.Uri := AUri;
  Context.Host := AHost;
  Context.Actions := TList<TProc>.Create;
  try
    Result := Command.Execute(Context, AEdits, AReason);
    if Result then
    begin
      AEdits := Reindent(AText, AEdits, AStyle);
      for Action in Context.Actions do
        Action();
    end
    else
    begin
      AEdits := nil;
      if AReason = '' then
        AReason := Format('Schnellbefehl /%s passt hier nicht', [Context.Name]);
    end;
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
  Edits: TArray<TTextEdit>;
  Problem: TSlashProblem;
begin
  Result := nil;
  Tokens := nil;
  Lines := TTextLines.SplitLines(AText, LineBreak);
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
