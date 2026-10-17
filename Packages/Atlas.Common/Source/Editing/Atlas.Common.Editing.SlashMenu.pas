unit Atlas.Common.Editing.SlashMenu;

// Erzeugen-Menü (#719) auf Grundlage der Schnellbefehle (#293, Teil
// „erlaubte Orte“ und „Argument-Vervollständigung“): Der Katalog nennt je
// Befehl, der etwas erzeugt oder Anweisungen umschließt, die erlaubten Orte
// (Ortsregel), die Gruppe, die Art des Arguments und ob es eine Auswahl
// möglicher Argumente gibt. Befehle ohne Eintrag (Pflege, Projekt, Umbauten
// wie /format) erscheinen nicht im Menü; über "/" bleiben sie erreichbar.
//
// Ausgeführt wird über eine gedachte Befehlszeile, ohne dass etwas im Editor
// getippt wird: Sie kommt vor die Cursorzeile, wenn diese leer ist, sonst
// dahinter, und mit Markierung vor deren erste Zeile; dann begrenzt
// TSlashContext.WrapUntil das Umschließen auf die Markierung. Der Befehl
// läuft auf diesem Text wie nach Enter, seine Änderungen werden auf den
// ursprünglichen Text umgerechnet (dort gibt es die gedachte Zeile nicht).
// Die Orte an der Cursorstelle bestimmt dieselbe gedachte Zeile: Routine
// (begin … end), Klasse (Deklaration oder Methode), Record, Interface,
// interface- bzw. implementation-Abschnitt einer Unit und Programmdatei.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.SlashCommands;

type
  {$SCOPEDENUMS ON}
  /// <summary>Ort an der Cursorstelle bzw. erlaubter Ort eines Befehls.</summary>
  TSlashPlace = (Routine, ClassBody, RecordBody, InterfaceBody, UnitInterface, UnitImplementation, ProgramFile);
  /// <summary>Gruppe im Erzeugen-Menü; Umschließen nur mit Markierung.</summary>
  TSlashGroup = (Generate, Surround);
  TSlashArgument = (None, Optional, Required);
  {$SCOPEDENUMS OFF}
  TSlashPlaces = set of TSlashPlace;

  TSlashMenuEntry = record
    Name: string;
    Places: TSlashPlaces;
    Group: TSlashGroup;
    Argument: TSlashArgument;
    /// <summary>Mehrere Werte wählbar (Felder für /ctor, Operatoren); sie werden mit Separator verbunden.</summary>
    Multi: Boolean;
    Separator: string;
    /// <summary>Choices liefert mögliche Argumente (Felder, Methoden zum Überschreiben, Botschaften …).</summary>
    HasChoices: Boolean;
  end;

  /// <summary>Stelle im Editor: Zeile und Zeichen des Cursors (ab 0) und letzte Zeile der Markierung (-1 ohne).
  /// </summary>
  TSlashSpot = record
    Line: Integer;
    Character: Integer;
    EndLine: Integer;
    class function Create(ALine, ACharacter, AEndLine: Integer): TSlashSpot; static;
    function HasSelection: Boolean;
  end;

  TSlashMenu = class
  public
    /// <summary>Alle Befehle des Menüs in Menüreihenfolge.</summary>
    class function Catalog: TArray<TSlashMenuEntry>; static;
    class function Find(const AName: string; out AEntry: TSlashMenuEntry): Boolean; static;
    /// <summary>Name im Protokoll: routine, class, record, interfaceType, interface, implementation, program.</summary>
    class function PlaceName(APlace: TSlashPlace): string; static;
    class function PlaceNames(APlaces: TSlashPlaces): TArray<string>; static;
    /// <summary>generate bzw. surround.</summary>
    class function GroupName(AGroup: TSlashGroup): string; static;
    /// <summary>none, optional bzw. required.</summary>
    class function ArgumentName(AArgument: TSlashArgument): string; static;
    /// <summary>Passt AEntry an Orte APlaces? Umschließen braucht eine Markierung in einer Routine.</summary>
    class function Fits(const AEntry: TSlashMenuEntry; APlaces: TSlashPlaces; AHasSelection: Boolean): Boolean; static;
    /// <summary>AText mit der gedachten Befehlszeile ACommand (z. B. "/ctor") an ASpot. ACommandLine ist ihre Zeile,
    /// AWrapUntil mit Markierung die Zeile hinter der Markierung (sonst 0). False, wenn ASpot außerhalb liegt.
    /// </summary>
    class function Prepare(const AText: string; const ASpot: TSlashSpot; const ACommand: string; out AVirtual: string;
      out ACommandLine, AWrapUntil: Integer): Boolean; static;
    /// <summary>Orte an ASpot; leer in Kommentaren, Strings und asm.</summary>
    class function PlacesAt(const AText: string; const ASpot: TSlashSpot): TSlashPlaces; static;
    /// <summary>Mögliche Argumente des Befehls AName an ASpot; AIndex für Vorfahren aus anderen Units (nil ohne).
    /// </summary>
    class function Choices(const AText: string; const ASpot: TSlashSpot; const AName: string;
      const AIndex: ISymbolIndex): TArray<string>; static;
    /// <summary>Vorschläge beim Tippen der Argumente in der Befehlszeile ALine von AText (AArguments bis zum
    /// Cursor): /sort und /filter erst Sammlungen, dann Felder und Properties des Elementtyps (#319).</summary>
    class function ArgumentChoices(const AText: string; ALine: Integer; const AName, AArguments: string;
      const AIndex: ISymbolIndex): TArray<string>; static;
    /// <summary>Führt "/AName AArguments" an ASpot aus; AEdits beziehen sich auf AText. False mit AReason, wenn der
    /// Befehl dort nicht passt oder abgeschaltet ist.</summary>
    class function Run(ARegistry: TSlashCommandRegistry; const AText: string; const ASpot: TSlashSpot; const AName,
      AArguments: string; const ADisabled: TArray<string>; const AIndex: ISymbolIndex; const ADelphiVersion,
      AUri: string; const AHost: ISlashHost; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean; static;
    /// <summary>Rechnet Änderungen am Text mit der gedachten Zeile ACommandLine (Text ACommandText) auf den Text
    /// ohne sie um. Was die Änderungen von der Zeile nicht überdecken (Einrückung davor, Zeilenende), bleibt wie
    /// im gedachten Text erhalten.</summary>
    class function MapEdits(const AEdits: TArray<TTextEdit>; ACommandLine: Integer; const ACommandText,
      ALineBreak: string): TArray<TTextEdit>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Editing.ClassCommands,
  Atlas.Common.Editing.CollectionCommands,
  Atlas.Common.Editing.RecordCommands;

const
  /// <summary>Häufige Symbole für /ifdef.</summary>
  IfdefSymbols: array[0..9] of string = ('DEBUG', 'RELEASE', 'MSWINDOWS', 'WIN32', 'WIN64', 'POSIX', 'LINUX',
    'MACOS', 'ANDROID', 'IOS');

{ TSlashSpot }

class function TSlashSpot.Create(ALine, ACharacter, AEndLine: Integer): TSlashSpot;
begin
  Result.Line := ALine;
  Result.Character := ACharacter;
  Result.EndLine := AEndLine;
end;

function TSlashSpot.HasSelection: Boolean;
begin
  Result := EndLine >= Line;
end;

{ Hilfen }

function Entry(const AName: string; APlaces: TSlashPlaces; AGroup: TSlashGroup; AArgument: TSlashArgument;
  AHasChoices, AMulti: Boolean; const ASeparator: string): TSlashMenuEntry; overload;
begin
  Result := Default(TSlashMenuEntry);
  Result.Name := AName;
  Result.Places := APlaces;
  Result.Group := AGroup;
  Result.Argument := AArgument;
  Result.HasChoices := AHasChoices;
  Result.Multi := AMulti;
  Result.Separator := ASeparator;
end;

function Entry(const AName: string; APlaces: TSlashPlaces; AGroup: TSlashGroup;
  AArgument: TSlashArgument): TSlashMenuEntry; overload;
begin
  Result := Entry(AName, APlaces, AGroup, AArgument, False, False, '');
end;

function LongerOf(const A, B: string): string;
begin
  if Length(B) > Length(A) then
    Result := B
  else
    Result := A;
end;

{ TSlashMenu }

class function TSlashMenu.Catalog: TArray<TSlashMenuEntry>;
const
  InClass = [TSlashPlace.ClassBody];
  InRoutine = [TSlashPlace.Routine];
  InUnit = [TSlashPlace.UnitInterface, TSlashPlace.UnitImplementation];
  Everywhere = [TSlashPlace.Routine, TSlashPlace.ClassBody, TSlashPlace.RecordBody, TSlashPlace.InterfaceBody,
    TSlashPlace.UnitInterface, TSlashPlace.UnitImplementation, TSlashPlace.ProgramFile];
begin
  // Reihenfolge wie im Menü: zuerst die Klasse (Mockup AC7), dann Records, Routinen und die Unit-Ebene.
  Result := [
    Entry('ctor', InClass, TSlashGroup.Generate, TSlashArgument.Optional, True, True, ', '),
    Entry('dtor', InClass, TSlashGroup.Generate, TSlashArgument.None),
    Entry('prop', InClass, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('override', InClass, TSlashGroup.Generate, TSlashArgument.Required, True, False, ''),
    Entry('equals', [TSlashPlace.ClassBody, TSlashPlace.RecordBody], TSlashGroup.Generate,
      TSlashArgument.Optional, True, True, ', '),
    // impl erst nach equals: Reihenfolge wie im Entwurf (AC7); der Server setzt „implement“ hinter override.
    Entry('impl', InClass, TSlashGroup.Generate, TSlashArgument.None),
    Entry('field', InClass, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('encapsulate', InClass, TSlashGroup.Generate, TSlashArgument.Required, True, False, ''),
    Entry('clone', InClass, TSlashGroup.Generate, TSlashArgument.None),
    Entry('assign', InClass, TSlashGroup.Generate, TSlashArgument.None),
    Entry('json', InClass, TSlashGroup.Generate, TSlashArgument.None),
    Entry('msg', InClass, TSlashGroup.Generate, TSlashArgument.Required, True, False, ''),
    Entry('intf', InClass, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('event', [TSlashPlace.ClassBody, TSlashPlace.Routine], TSlashGroup.Generate, TSlashArgument.Required),
    Entry('notify', InClass, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('changed', InClass, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('loaded', InClass, TSlashGroup.Generate, TSlashArgument.None),
    Entry('notification', InClass, TSlashGroup.Generate, TSlashArgument.Optional),
    Entry('singleton', InClass, TSlashGroup.Generate, TSlashArgument.None),
    Entry('list', [TSlashPlace.ClassBody, TSlashPlace.Routine], TSlashGroup.Generate, TSlashArgument.Required),
    Entry('dict', [TSlashPlace.ClassBody, TSlashPlace.Routine], TSlashGroup.Generate, TSlashArgument.Required),
    Entry('dict!', [TSlashPlace.ClassBody, TSlashPlace.Routine], TSlashGroup.Generate, TSlashArgument.Required),
    Entry('sort', InRoutine, TSlashGroup.Generate, TSlashArgument.Required, True, False, ''),
    Entry('filter', InRoutine, TSlashGroup.Generate, TSlashArgument.Required, True, False, ''),
    Entry('operator', [TSlashPlace.RecordBody], TSlashGroup.Generate, TSlashArgument.Required, True, True, ' '),
    Entry('guid', [TSlashPlace.InterfaceBody], TSlashGroup.Generate, TSlashArgument.None),
    Entry('var', InRoutine, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('const', InRoutine, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('const!', [TSlashPlace.Routine, TSlashPlace.UnitImplementation], TSlashGroup.Generate,
      TSlashArgument.Required),
    Entry('guard', InRoutine, TSlashGroup.Generate, TSlashArgument.Optional),
    Entry('raise', InRoutine, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('log', InRoutine, TSlashGroup.Generate, TSlashArgument.None),
    Entry('sql', InRoutine, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('params', InRoutine, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('case', InRoutine, TSlashGroup.Generate, TSlashArgument.None),
    Entry('test', InRoutine, TSlashGroup.Generate, TSlashArgument.None),
    Entry('record', InUnit, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('enum', InUnit, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('enum!', InUnit, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('helper', InUnit, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('exception', InUnit, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('thread', InUnit, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('external', InUnit, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('exports', [TSlashPlace.ProgramFile], TSlashGroup.Generate, TSlashArgument.None),
    Entry('todo', Everywhere, TSlashGroup.Generate, TSlashArgument.Required),
    // Umschließen (#296, #304, #302, #322): nur mit Markierung im Rumpf einer Routine.
    Entry('try', InRoutine, TSlashGroup.Surround, TSlashArgument.None),
    Entry('except', InRoutine, TSlashGroup.Surround, TSlashArgument.None),
    Entry('lock', InRoutine, TSlashGroup.Surround, TSlashArgument.None),
    Entry('sync', InRoutine, TSlashGroup.Surround, TSlashArgument.None),
    Entry('sync!', InRoutine, TSlashGroup.Surround, TSlashArgument.None),
    Entry('ifdef', InRoutine, TSlashGroup.Surround, TSlashArgument.Required, True, False, ''),
    Entry('region', InRoutine, TSlashGroup.Surround, TSlashArgument.Required),
    Entry('measure', InRoutine, TSlashGroup.Surround, TSlashArgument.Optional),
    Entry('task', InRoutine, TSlashGroup.Surround, TSlashArgument.None),
    Entry('future', InRoutine, TSlashGroup.Surround, TSlashArgument.Required),
    Entry('loop', InRoutine, TSlashGroup.Surround, TSlashArgument.Required),
    Entry('transaction', InRoutine, TSlashGroup.Surround, TSlashArgument.Required)];
end;

class function TSlashMenu.Find(const AName: string; out AEntry: TSlashMenuEntry): Boolean;
var
  Item: TSlashMenuEntry;
begin
  for Item in Catalog do
    if SameText(Item.Name, AName) then
    begin
      AEntry := Item;
      Exit(True);
    end;
  AEntry := Default(TSlashMenuEntry);
  Result := False;
end;

class function TSlashMenu.PlaceName(APlace: TSlashPlace): string;
begin
  case APlace of
    TSlashPlace.Routine:
      Result := 'routine';
    TSlashPlace.ClassBody:
      Result := 'class';
    TSlashPlace.RecordBody:
      Result := 'record';
    TSlashPlace.InterfaceBody:
      Result := 'interfaceType';
    TSlashPlace.UnitInterface:
      Result := 'interface';
    TSlashPlace.UnitImplementation:
      Result := 'implementation';
  else
    Result := 'program';
  end;
end;

class function TSlashMenu.PlaceNames(APlaces: TSlashPlaces): TArray<string>;
var
  Place: TSlashPlace;
begin
  Result := nil;
  for Place := Low(TSlashPlace) to High(TSlashPlace) do
    if Place in APlaces then
      Result := Result + [PlaceName(Place)];
end;

class function TSlashMenu.GroupName(AGroup: TSlashGroup): string;
begin
  if AGroup = TSlashGroup.Surround then
    Result := 'surround'
  else
    Result := 'generate';
end;

class function TSlashMenu.ArgumentName(AArgument: TSlashArgument): string;
begin
  case AArgument of
    TSlashArgument.Optional:
      Result := 'optional';
    TSlashArgument.Required:
      Result := 'required';
  else
    Result := 'none';
  end;
end;

class function TSlashMenu.Fits(const AEntry: TSlashMenuEntry; APlaces: TSlashPlaces; AHasSelection: Boolean): Boolean;
begin
  Result := AEntry.Places * APlaces <> [];
  if AEntry.Group = TSlashGroup.Surround then
    Result := Result and AHasSelection;
end;

class function TSlashMenu.Prepare(const AText: string; const ASpot: TSlashSpot; const ACommand: string;
  out AVirtual: string; out ACommandLine, AWrapUntil: Integer): Boolean;
var
  Lines: TArray<string>;
  LineBreak, Indent, Current: string;
  Index: Integer;
begin
  AVirtual := '';
  ACommandLine := -1;
  AWrapUntil := 0;
  Lines := TTextLines.SplitLines(AText, LineBreak);
  if (ASpot.Line < 0) or (ASpot.Line > High(Lines)) then
    Exit(False);
  Current := Lines[ASpot.Line];
  if ASpot.HasSelection then
  begin
    // Vor die Markierung, eingerückt wie ihre erste Zeile mit Text; umschlossen wird nur sie.
    ACommandLine := ASpot.Line;
    Indent := TTextLines.IndentOf(Current);
    for Index := ASpot.Line to Min(ASpot.EndLine, High(Lines)) do
      if Trim(Lines[Index]) <> '' then
      begin
        Indent := TTextLines.IndentOf(Lines[Index]);
        Break;
      end;
    AWrapUntil := Min(ASpot.EndLine, High(Lines)) + 2;
  end
  else if Trim(Current) = '' then
  begin
    // Leere Zeile: an ihre Stelle; die IDE hält den Cursor oft hinter dem Zeilenende (eingerückt ohne Leerzeichen).
    ACommandLine := ASpot.Line;
    Indent := TTextLines.IndentOf(Current);
    if ASpot.Character > Length(Indent) then
      Indent := StringOfChar(' ', ASpot.Character);
  end
  else
  begin
    // Zeile mit Text: dahinter, eingerückt wie sie oder wie die nächste Zeile mit Text, falls tiefer.
    ACommandLine := ASpot.Line + 1;
    Indent := TTextLines.IndentOf(Current);
    for Index := ASpot.Line + 1 to High(Lines) do
      if Trim(Lines[Index]) <> '' then
      begin
        Indent := LongerOf(Indent, TTextLines.IndentOf(Lines[Index]));
        Break;
      end;
  end;
  Insert(Indent + ACommand, Lines, ACommandLine);
  AVirtual := TTextLines.JoinLines(Lines, LineBreak);
  Result := True;
end;

class function TSlashMenu.PlacesAt(const AText: string; const ASpot: TSlashSpot): TSlashPlaces;
var
  Virtual: string;
  CommandLine, WrapUntil, ImplementationLine: Integer;
  Tokens: TArray<TPascalToken>;
  Token: TPascalToken;
  Context: TSlashContext;
  Source: TCommandSource;
  Symbol, ClassSymbol: TIndexSymbol;
  First: Boolean;
begin
  Result := [];
  if not Prepare(AText, ASpot, '/x', Virtual, CommandLine, WrapUntil) then
    Exit;
  Tokens := TPascalLexer.Tokenize(Virtual);
  if not TSlashCommandRegistry.IsCodeLine(Tokens, CommandLine) then
    Exit;
  Context := Default(TSlashContext);
  Context.Text := Virtual;
  Context.Line := CommandLine;
  Context.Name := 'x';
  Source := TCommandSource.Create(Context);
  try
    if Source.RoutineAt <> nil then
      Include(Result, TSlashPlace.Routine);
    if Source.ClassAt(ClassSymbol) then
      Include(Result, TSlashPlace.ClassBody);
    if Result <> [] then
      Exit;
    for Symbol in Source.UnitIndex.Symbols do
    begin
      if (Symbol.Range.StartPos.Line >= CommandLine) or (Symbol.Range.EndPos.Line <= CommandLine) then
        Continue;
      if Symbol.Kind = TIndexSymbolKind.RecordType then
        Include(Result, TSlashPlace.RecordBody)
      else if Symbol.Kind = TIndexSymbolKind.InterfaceType then
        Include(Result, TSlashPlace.InterfaceBody);
    end;
    if Result <> [] then
      Exit;
  finally
    Source.Free;
  end;
  // Unit-Ebene: Programmdatei am ersten Wort, sonst vor oder hinter "implementation".
  First := True;
  ImplementationLine := -1;
  for Token in Tokens do
  begin
    if Token.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
      Continue;
    if First and (Token.IsKeyword('program') or Token.IsKeyword('library')) then
      Exit([TSlashPlace.ProgramFile]);
    First := False;
    if Token.IsKeyword('implementation') then
    begin
      ImplementationLine := Token.StartPos.Line;
      Break;
    end;
  end;
  if (ImplementationLine >= 0) and (CommandLine > ImplementationLine) then
    Result := [TSlashPlace.UnitImplementation]
  else
    Result := [TSlashPlace.UnitInterface];
end;

/// <summary>Felder mit F-Präfix ohne gleichnamige Property in der Klasse um die Befehlszeile (/encapsulate).</summary>
function EncapsulateFields(const AContext: TSlashContext): TArray<string>;
var
  Source: TCommandSource;
  ClassSymbol, Symbol, Other: TIndexSymbol;
  HasProperty: Boolean;
begin
  Result := nil;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
      Exit;
    for Symbol in Source.UnitIndex.Symbols do
      if (Symbol.Kind = TIndexSymbolKind.Field) and SameText(Symbol.Container, ClassSymbol.Name) and
        (Length(Symbol.Name) > 1) and CharInSet(Symbol.Name[1], ['F', 'f']) then
      begin
        HasProperty := False;
        for Other in Source.UnitIndex.Symbols do
          if (Other.Kind = TIndexSymbolKind.Property_) and SameText(Other.Container, ClassSymbol.Name) and
            SameText(Other.Name, Copy(Symbol.Name, 2, MaxInt)) then
            HasProperty := True;
        if not HasProperty then
          Result := Result + [Symbol.Name];
      end;
  finally
    Source.Free;
  end;
end;

class function TSlashMenu.Choices(const AText: string; const ASpot: TSlashSpot; const AName: string;
  const AIndex: ISymbolIndex): TArray<string>;
var
  Virtual: string;
  CommandLine, WrapUntil: Integer;
  Context: TSlashContext;
  Symbol: string;
begin
  Result := nil;
  if SameText(AName, 'msg') then
    Exit(MessageNames);
  if SameText(AName, 'operator') then
    Exit(OperatorTokens);
  if SameText(AName, 'ifdef') then
  begin
    for Symbol in IfdefSymbols do
      Result := Result + [Symbol];
    Exit;
  end;
  if not Prepare(AText, ASpot, '/' + AName, Virtual, CommandLine, WrapUntil) then
    Exit;
  Context := Default(TSlashContext);
  Context.Text := Virtual;
  Context.Line := CommandLine;
  Context.Name := AName;
  Context.Index := AIndex;
  if SameText(AName, 'ctor') then
    Result := CtorFields(Context)
  else if SameText(AName, 'override') then
    Result := OverrideCandidates(Context)
  else if SameText(AName, 'equals') then
    Result := EqualsFields(Context)
  else if SameText(AName, 'encapsulate') then
    Result := EncapsulateFields(Context)
  else if SameText(AName, 'sort') or SameText(AName, 'filter') then
    Result := CollectionChoices(Context, '');
end;

class function TSlashMenu.ArgumentChoices(const AText: string; ALine: Integer; const AName, AArguments: string;
  const AIndex: ISymbolIndex): TArray<string>;
var
  Context: TSlashContext;
  Space: Integer;
begin
  Result := nil;
  if not SameText(AName, 'sort') and not SameText(AName, 'filter') then
    Exit;
  Context := Default(TSlashContext);
  Context.Text := AText;
  Context.Line := ALine;
  Context.Name := AName;
  Context.Index := AIndex;
  // Erst die Sammlung, nach dem Leerzeichen die Mitglieder ihres Elementtyps.
  Space := Pos(' ', TrimLeft(AArguments));
  if Space = 0 then
    Result := CollectionChoices(Context, '')
  else
    Result := CollectionChoices(Context, Copy(TrimLeft(AArguments), 1, Space - 1));
end;

class function TSlashMenu.Run(ARegistry: TSlashCommandRegistry; const AText: string; const ASpot: TSlashSpot;
  const AName, AArguments: string; const ADisabled: TArray<string>; const AIndex: ISymbolIndex;
  const ADelphiVersion, AUri: string; const AHost: ISlashHost; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  Virtual, Command, LineBreak: string;
  CommandLine, WrapUntil: Integer;
  Edits: TArray<TTextEdit>;
  Lines: TArray<string>;
begin
  AEdits := nil;
  AReason := '';
  Command := '/' + AName;
  if Trim(AArguments) <> '' then
    Command := Command + ' ' + Trim(AArguments);
  if not Prepare(AText, ASpot, Command, Virtual, CommandLine, WrapUntil) then
  begin
    AReason := 'Die Cursorstelle liegt außerhalb der Datei';
    Exit(False);
  end;
  Result := ARegistry.Run(Virtual, CommandLine, WrapUntil, nil, ADisabled, AIndex, ADelphiVersion, AUri, AHost,
    Edits, AReason);
  if not Result then
    Exit;
  LineBreak := TTextLines.LineBreakOf(AText);
  Lines := TTextLines.SplitLines(Virtual);
  AEdits := MapEdits(Edits, CommandLine, Lines[CommandLine], LineBreak);
end;

class function TSlashMenu.MapEdits(const AEdits: TArray<TTextEdit>; ACommandLine: Integer; const ACommandText,
  ALineBreak: string): TArray<TTextEdit>;
var
  Edit: TTextEdit;
  Mapped: TArray<TTextEdit>;
  Index, FirstStart, FirstEdit, LastEnd, LastEdit: Integer;
  BreakCovered: Boolean;
  Indent: string;

  function Map(const APosition: TTextPosition): TTextPosition;
  begin
    if APosition.Line < ACommandLine then
      Result := APosition
    else if APosition.Line = ACommandLine then
      Result := TTextPosition.Create(ACommandLine, 0)
    else
      Result := TTextPosition.Create(APosition.Line - 1, APosition.Character);
  end;

begin
  // Was von der gedachten Zeile nicht überdeckt wird, bleibt im gedachten Ergebnis stehen: der Anfang vor der
  // ersten Änderung in der Zeile und ihr Zeilenende, wenn keine Änderung darüber hinausreicht.
  FirstStart := MaxInt;
  FirstEdit := -1;
  LastEnd := -1;
  LastEdit := -1;
  BreakCovered := False;
  for Index := 0 to High(AEdits) do
  begin
    Edit := AEdits[Index];
    if (Edit.Range.StartPos.Line <= ACommandLine) and (Edit.Range.EndPos.Line > ACommandLine) then
      BreakCovered := True;
    if (Edit.Range.StartPos.Line = ACommandLine) and (Edit.Range.StartPos.Character < FirstStart) then
    begin
      FirstStart := Edit.Range.StartPos.Character;
      FirstEdit := Index;
    end;
    if (Edit.Range.StartPos.Line < ACommandLine) and (Edit.Range.EndPos.Line >= ACommandLine) then
    begin
      FirstStart := 0;
      FirstEdit := -1;
    end;
    if (Edit.Range.EndPos.Line = ACommandLine) and (Edit.Range.EndPos.Character > LastEnd) then
    begin
      LastEnd := Edit.Range.EndPos.Character;
      LastEdit := Index;
    end;
  end;
  // Nur die Einrückung vor dem Befehl kann stehen bleiben, nie der Befehl selbst.
  Indent := '';
  if (FirstEdit >= 0) and (FirstStart > 0) then
    Indent := Copy(ACommandText, 1, Min(FirstStart, Length(TTextLines.IndentOf(ACommandText))));
  Mapped := nil;
  for Index := 0 to High(AEdits) do
  begin
    Edit := TTextEdit.Create(TTextRange.Create(Map(AEdits[Index].Range.StartPos), Map(AEdits[Index].Range.EndPos)),
      AEdits[Index].NewText);
    if Index = FirstEdit then
      Edit.NewText := Indent + Edit.NewText;
    if (Index = LastEdit) and not BreakCovered then
      Edit.NewText := Edit.NewText + ALineBreak;
    if (Edit.Range.StartPos = Edit.Range.EndPos) and (Edit.NewText = '') then
      Continue;
    Mapped := Mapped + [Edit];
  end;
  Result := Mapped;
end;

end.
