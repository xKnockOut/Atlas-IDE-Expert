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
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.Contract;

type
  {$SCOPEDENUMS ON}
  /// <summary>Ort an der Cursorstelle bzw. erlaubter Ort eines Befehls.</summary>
  TSlashPlace = (Routine, ClassBody, RecordBody, InterfaceBody, UnitInterface, UnitImplementation, ProgramFile);
  /// <summary>Gruppe im Erzeugen-Menü; Umschließen nur mit Markierung.</summary>
  TSlashGroup = (Generate, Surround);
  TSlashArgument = (None, Optional, Required);
  /// <summary>Art der Vorschläge beim Tippen der Argumente (#293).</summary>
  TSlashArgumentKind = (None, Collection, Units, Types, Interfaces, Exceptions, Overrides, Rules);
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

  /// <summary>Befehl, den das Erzeugen-Menü ausführt: "/Name Arguments" in der Umgebung Environment.</summary>
  TSlashMenuCall = record
    Name: string;
    Arguments: string;
    Environment: TSlashEnvironment;
    class function Create(const AName, AArguments: string;
      const AEnvironment: TSlashEnvironment): TSlashMenuCall; static;
  end;

  TSlashMenu = class
  public const
    /// <summary>Höchstzahl der Vorschläge aus dem Index beim Tippen der Argumente.</summary>
    MaxChoices = 200;
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
    /// Cursor, #293): /sort und /filter erst Sammlungen, dann Felder und Properties des Elementtyps (#319);
    /// /uses und /open Units; Typen hinter dem ":" von /var, /field, /prop, /list, /future und als Argument von
    /// /helper; Interfaces bei /intf, Ausnahmeklassen bei /raise und /exception; überschreibbare Methoden bei
    /// /override; Regelkennungen aus ARuleIds bei /ignore. Gefiltert nach dem angefangenen Wort, höchstens
    /// MaxChoices.</summary>
    class function ArgumentChoices(const AText: string; ALine: Integer; const AName, AArguments: string;
      const AIndex: ISymbolIndex; const ARuleIds: TArray<string>): TArray<string>; overload; static;
    /// <summary>Wie oben, ohne Regelkennungen.</summary>
    class function ArgumentChoices(const AText: string; ALine: Integer; const AName, AArguments: string;
      const AIndex: ISymbolIndex): TArray<string>; overload; static;
    /// <summary>Art der Vorschläge für "/AName AArguments" (#293); bei Typen ergänzt die Vervollständigung den
    /// uses-Eintrag der gewählten Typ-Unit (#294, #180).</summary>
    class function ArgumentKind(const AName, AArguments: string): TSlashArgumentKind; static;
    /// <summary>Das angefangene Wort am Ende von AArguments (nach Leerzeichen, Komma oder Doppelpunkt).</summary>
    class function CurrentWord(const AArguments: string): string; static;
    /// <summary>Führt ACall an ASpot aus; AEdits beziehen sich auf AText. False mit AReason, wenn der Befehl dort
    /// nicht passt oder abgeschaltet ist.</summary>
    class function Run(ARegistry: TSlashCommandRegistry; const AText: string; const ASpot: TSlashSpot;
      const ACall: TSlashMenuCall; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean; static;
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
  Atlas.Common.Editing.RecordCommands,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TEditingSlashMenuText = (TheCursorPositionLiesOutside);

const
  cTexts: array[TEditingSlashMenuText] of TAtlasText = (
    (De: 'Die Cursorstelle liegt außerhalb der Datei'; En: 'The cursor position lies outside the file'));

{$SCOPEDENUMS OFF}

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

{ TSlashMenuCall }

class function TSlashMenuCall.Create(const AName, AArguments: string;
  const AEnvironment: TSlashEnvironment): TSlashMenuCall;
begin
  Result.Name := AName;
  Result.Arguments := AArguments;
  Result.Environment := AEnvironment;
end;

{ Hilfen }

function Entry(const AName: string; APlaces: TSlashPlaces; AGroup: TSlashGroup;
  AArgument: TSlashArgument): TSlashMenuEntry;
begin
  Result := Default(TSlashMenuEntry);
  Result.Name := AName;
  Result.Places := APlaces;
  Result.Group := AGroup;
  Result.Argument := AArgument;
end;

/// <summary>Eintrag mit Auswahl möglicher Argumente (Choices).</summary>
function ChoiceEntry(const AName: string; APlaces: TSlashPlaces; AGroup: TSlashGroup;
  AArgument: TSlashArgument): TSlashMenuEntry;
begin
  Result := Entry(AName, APlaces, AGroup, AArgument);
  Result.HasChoices := True;
end;

/// <summary>Eintrag mit Auswahl mehrerer Argumente, verbunden mit ASeparator.</summary>
function MultiEntry(const AName: string; APlaces: TSlashPlaces; AGroup: TSlashGroup; AArgument: TSlashArgument;
  const ASeparator: string): TSlashMenuEntry;
begin
  Result := ChoiceEntry(AName, APlaces, AGroup, AArgument);
  Result.Multi := True;
  Result.Separator := ASeparator;
end;

function LongerOf(const A, B: string): string;
begin
  if Length(B) > Length(A) then
  begin
    Result := B;
  end
  else
  begin
    Result := A;
  end;
end;

const
  InClass = [TSlashPlace.ClassBody];
  InRoutine = [TSlashPlace.Routine];
  InUnit = [TSlashPlace.UnitInterface, TSlashPlace.UnitImplementation];
  Everywhere = [TSlashPlace.Routine, TSlashPlace.ClassBody, TSlashPlace.RecordBody, TSlashPlace.InterfaceBody,
    TSlashPlace.UnitInterface, TSlashPlace.UnitImplementation, TSlashPlace.ProgramFile];

/// <summary>Erzeugen in der Klasse (Mockup AC7).</summary>
function ClassEntries: TArray<TSlashMenuEntry>;
begin
  Result := [
    MultiEntry('ctor', InClass, TSlashGroup.Generate, TSlashArgument.Optional, ', '),
    Entry('dtor', InClass, TSlashGroup.Generate, TSlashArgument.None),
    Entry('prop', InClass, TSlashGroup.Generate, TSlashArgument.Required),
    ChoiceEntry('override', InClass, TSlashGroup.Generate, TSlashArgument.Required),
    MultiEntry('equals', [TSlashPlace.ClassBody, TSlashPlace.RecordBody], TSlashGroup.Generate,
      TSlashArgument.Optional, ', '),
    // impl erst nach equals: Reihenfolge wie im Entwurf (AC7); der Server setzt „implement“ hinter override.
    Entry('impl', InClass, TSlashGroup.Generate, TSlashArgument.None),
    Entry('field', InClass, TSlashGroup.Generate, TSlashArgument.Required),
    ChoiceEntry('encapsulate', InClass, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('clone', InClass, TSlashGroup.Generate, TSlashArgument.None),
    Entry('assign', InClass, TSlashGroup.Generate, TSlashArgument.None),
    Entry('json', InClass, TSlashGroup.Generate, TSlashArgument.None),
    ChoiceEntry('msg', InClass, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('intf', InClass, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('event', [TSlashPlace.ClassBody, TSlashPlace.Routine], TSlashGroup.Generate, TSlashArgument.Required),
    Entry('notify', InClass, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('changed', InClass, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('loaded', InClass, TSlashGroup.Generate, TSlashArgument.None),
    Entry('notification', InClass, TSlashGroup.Generate, TSlashArgument.Optional),
    Entry('singleton', InClass, TSlashGroup.Generate, TSlashArgument.None)];
end;

/// <summary>Erzeugen in Sammlungen, Records, Interfaces und Routinen.</summary>
function RoutineEntries: TArray<TSlashMenuEntry>;
begin
  Result := [
    Entry('list', [TSlashPlace.ClassBody, TSlashPlace.Routine], TSlashGroup.Generate, TSlashArgument.Required),
    Entry('dict', [TSlashPlace.ClassBody, TSlashPlace.Routine], TSlashGroup.Generate, TSlashArgument.Required),
    Entry('dict!', [TSlashPlace.ClassBody, TSlashPlace.Routine], TSlashGroup.Generate, TSlashArgument.Required),
    ChoiceEntry('sort', InRoutine, TSlashGroup.Generate, TSlashArgument.Required),
    ChoiceEntry('filter', InRoutine, TSlashGroup.Generate, TSlashArgument.Required),
    MultiEntry('operator', [TSlashPlace.RecordBody], TSlashGroup.Generate, TSlashArgument.Required, ' '),
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
    Entry('test', InRoutine, TSlashGroup.Generate, TSlashArgument.None)];
end;

/// <summary>Erzeugen auf Unit-Ebene und in der Programmdatei.</summary>
function UnitEntries: TArray<TSlashMenuEntry>;
begin
  Result := [
    Entry('record', InUnit, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('enum', InUnit, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('enum!', InUnit, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('helper', InUnit, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('exception', InUnit, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('thread', InUnit, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('external', InUnit, TSlashGroup.Generate, TSlashArgument.Required),
    Entry('exports', [TSlashPlace.ProgramFile], TSlashGroup.Generate, TSlashArgument.None),
    Entry('todo', Everywhere, TSlashGroup.Generate, TSlashArgument.Required)];
end;

/// <summary>Umschließen (#296, #304, #302, #322): nur mit Markierung im Rumpf einer Routine.</summary>
function SurroundEntries: TArray<TSlashMenuEntry>;
begin
  Result := [
    Entry('try', InRoutine, TSlashGroup.Surround, TSlashArgument.None),
    Entry('except', InRoutine, TSlashGroup.Surround, TSlashArgument.None),
    Entry('lock', InRoutine, TSlashGroup.Surround, TSlashArgument.None),
    Entry('sync', InRoutine, TSlashGroup.Surround, TSlashArgument.None),
    Entry('sync!', InRoutine, TSlashGroup.Surround, TSlashArgument.None),
    ChoiceEntry('ifdef', InRoutine, TSlashGroup.Surround, TSlashArgument.Required),
    Entry('region', InRoutine, TSlashGroup.Surround, TSlashArgument.Required),
    Entry('measure', InRoutine, TSlashGroup.Surround, TSlashArgument.Optional),
    Entry('task', InRoutine, TSlashGroup.Surround, TSlashArgument.None),
    Entry('future', InRoutine, TSlashGroup.Surround, TSlashArgument.Required),
    Entry('loop', InRoutine, TSlashGroup.Surround, TSlashArgument.Required),
    Entry('transaction', InRoutine, TSlashGroup.Surround, TSlashArgument.Required)];
end;

{ TSlashMenu }

class function TSlashMenu.Catalog: TArray<TSlashMenuEntry>;
begin
  // Reihenfolge wie im Menü: zuerst die Klasse (Mockup AC7), dann Records, Routinen und die Unit-Ebene.
  Result := ClassEntries + RoutineEntries + UnitEntries + SurroundEntries;
end;

class function TSlashMenu.Find(const AName: string; out AEntry: TSlashMenuEntry): Boolean;
var
  Item: TSlashMenuEntry;
begin
  for Item in Catalog do
  begin
    if SameText(Item.Name, AName) then
    begin
      AEntry := Item;
      Exit(True);
    end;
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
  begin
    if Place in APlaces then
    begin
      Result := Result + [PlaceName(Place)];
    end;
  end;
end;

class function TSlashMenu.GroupName(AGroup: TSlashGroup): string;
begin
  if AGroup = TSlashGroup.Surround then
  begin
    Result := 'surround';
  end
  else
  begin
    Result := 'generate';
  end;
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
  begin
    Result := Result and AHasSelection;
  end;
end;

/// <summary>Einrückung der ersten Zeile mit Text in ALines[AFirst..ALast]; ADefault ohne.</summary>
function FirstIndent(const ALines: TArray<string>; AFirst, ALast: Integer; const ADefault: string): string;
var
  mIndex: Integer;
begin
  Result := ADefault;
  for mIndex := AFirst to ALast do
  begin
    if Trim(ALines[mIndex]) <> '' then
    begin
      Exit(TTextLines.IndentOf(ALines[mIndex]));
    end;
  end;
end;

class function TSlashMenu.Prepare(const AText: string; const ASpot: TSlashSpot; const ACommand: string;
  out AVirtual: string; out ACommandLine, AWrapUntil: Integer): Boolean;
var
  mLines: TArray<string>;
  mLineBreak, mIndent, mCurrent: string;
begin
  AVirtual := '';
  ACommandLine := -1;
  AWrapUntil := 0;
  mLines := TTextLines.SplitLines(AText, mLineBreak);
  if (ASpot.Line < 0) or (ASpot.Line > High(mLines)) then
  begin
    Exit(False);
  end;
  mCurrent := mLines[ASpot.Line];
  mIndent := TTextLines.IndentOf(mCurrent);
  ACommandLine := ASpot.Line;
  if ASpot.HasSelection then
  begin
    // Vor die Markierung, eingerückt wie ihre erste Zeile mit Text; umschlossen wird nur sie.
    mIndent := FirstIndent(mLines, ASpot.Line, Min(ASpot.EndLine, High(mLines)), mIndent);
    AWrapUntil := Min(ASpot.EndLine, High(mLines)) + 2;
  end
  else if Trim(mCurrent) = '' then
  begin
    // Leere Zeile: an ihre Stelle; die IDE hält den Cursor oft hinter dem Zeilenende (eingerückt ohne Leerzeichen).
    if ASpot.Character > Length(mIndent) then
    begin
      mIndent := StringOfChar(' ', ASpot.Character);
    end;
  end
  else
  begin
    // Zeile mit Text: dahinter, eingerückt wie sie oder wie die nächste Zeile mit Text, falls tiefer.
    ACommandLine := ASpot.Line + 1;
    mIndent := LongerOf(mIndent, FirstIndent(mLines, ASpot.Line + 1, High(mLines), ''));
  end;
  Insert(mIndent + ACommand, mLines, ACommandLine);
  AVirtual := TTextLines.JoinLines(mLines, mLineBreak);
  Result := True;
end;

/// <summary>Record- bzw. Interface-Rumpf aus AIndex, der die Zeile ALine umschließt.</summary>
function BodyPlaces(const AIndex: TUnitIndex; ALine: Integer): TSlashPlaces;
var
  mSymbol: TIndexSymbol;
begin
  Result := [];
  for mSymbol in AIndex.Symbols do
  begin
    if (mSymbol.Range.StartPos.Line >= ALine) or (mSymbol.Range.EndPos.Line <= ALine) then
    begin
      Continue;
    end;
    if mSymbol.Kind = TIndexSymbolKind.RecordType then
    begin
      Include(Result, TSlashPlace.RecordBody);
    end
    else if mSymbol.Kind = TIndexSymbolKind.InterfaceType then
    begin
      Include(Result, TSlashPlace.InterfaceBody);
    end;
  end;
end;

/// <summary>Orte aus dem Syntaxbaum an der gedachten Befehlszeile ACommandLine von AVirtual: Routine und Klasse,
/// sonst Record- oder Interface-Rumpf; leer auf Unit-Ebene.</summary>
function TypePlaces(const AVirtual: string; ACommandLine: Integer): TSlashPlaces;
var
  mContext: TSlashContext;
  mSource: TCommandSource;
  mClassSymbol: TIndexSymbol;
begin
  Result := [];
  mContext := Default(TSlashContext);
  mContext.Text := AVirtual;
  mContext.Line := ACommandLine;
  mContext.Name := 'x';
  mSource := TCommandSource.Create(mContext);
  try
    if mSource.RoutineAt <> nil then
    begin
      Include(Result, TSlashPlace.Routine);
    end;
    if mSource.ClassAt(mClassSymbol) then
    begin
      Include(Result, TSlashPlace.ClassBody);
    end;
    if Result = [] then
    begin
      Result := BodyPlaces(mSource.UnitIndex, ACommandLine);
    end;
  finally
    mSource.Free;
  end;
end;

/// <summary>Unit-Ebene: Programmdatei am ersten Wort, sonst vor oder hinter "implementation".</summary>
function UnitPlaces(const ATokens: TArray<TPascalToken>; ACommandLine: Integer): TSlashPlaces;
var
  mToken: TPascalToken;
  mFirst: Boolean;
  mImplementationLine: Integer;
begin
  mFirst := True;
  mImplementationLine := -1;
  for mToken in ATokens do
  begin
    if mToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
    begin
      Continue;
    end;
    if mFirst and (mToken.IsKeyword('program') or mToken.IsKeyword('library')) then
    begin
      Exit([TSlashPlace.ProgramFile]);
    end;
    mFirst := False;
    if mToken.IsKeyword('implementation') then
    begin
      mImplementationLine := mToken.StartPos.Line;
      Break;
    end;
  end;
  if (mImplementationLine >= 0) and (ACommandLine > mImplementationLine) then
  begin
    Result := [TSlashPlace.UnitImplementation];
  end
  else
  begin
    Result := [TSlashPlace.UnitInterface];
  end;
end;

class function TSlashMenu.PlacesAt(const AText: string; const ASpot: TSlashSpot): TSlashPlaces;
var
  mVirtual: string;
  mCommandLine, mWrapUntil: Integer;
  mTokens: TArray<TPascalToken>;
begin
  Result := [];
  if not Prepare(AText, ASpot, '/x', mVirtual, mCommandLine, mWrapUntil) then
  begin
    Exit;
  end;
  mTokens := TPascalLexer.Tokenize(mVirtual);
  if TSlashCommandRegistry.IsCodeLine(mTokens, mCommandLine) then
  begin
    Result := TypePlaces(mVirtual, mCommandLine);
    if Result = [] then
    begin
      Result := UnitPlaces(mTokens, mCommandLine);
    end;
  end;
end;

/// <summary>Ist ASymbol ein Feld der Klasse AClassName mit F-Präfix?</summary>
function IsPrefixedField(const ASymbol: TIndexSymbol; const AClassName: string): Boolean;
begin
  Result := (ASymbol.Kind = TIndexSymbolKind.Field) and SameText(ASymbol.Container, AClassName) and
    (Length(ASymbol.Name) > 1) and CharInSet(ASymbol.Name[1], ['F', 'f']);
end;

/// <summary>Hat die Klasse AClassName eine Property zum Feld AFieldName (Name ohne F)?</summary>
function HasPropertyFor(const AIndex: TUnitIndex; const AClassName, AFieldName: string): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AIndex.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.Property_) and SameText(mSymbol.Container, AClassName) and
      SameText(mSymbol.Name, Copy(AFieldName, 2, MaxInt)) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Felder mit F-Präfix ohne gleichnamige Property in der Klasse um die Befehlszeile (/encapsulate).</summary>
function EncapsulateFields(const AContext: TSlashContext): TArray<string>;
var
  mSource: TCommandSource;
  mClassSymbol, mSymbol: TIndexSymbol;
begin
  Result := nil;
  mSource := TCommandSource.Create(AContext);
  try
    if not mSource.ClassAt(mClassSymbol) then
    begin
      Exit;
    end;
    for mSymbol in mSource.UnitIndex.Symbols do
    begin
      if IsPrefixedField(mSymbol, mClassSymbol.Name) and
        not HasPropertyFor(mSource.UnitIndex, mClassSymbol.Name, mSymbol.Name) then
      begin
        Result := Result + [mSymbol.Name];
      end;
    end;
  finally
    mSource.Free;
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
  begin
    Exit(MessageNames);
  end;
  if SameText(AName, 'operator') then
  begin
    Exit(OperatorTokens);
  end;
  if SameText(AName, 'ifdef') then
  begin
    for Symbol in IfdefSymbols do
    begin
      Result := Result + [Symbol];
    end;
    Exit;
  end;
  if not Prepare(AText, ASpot, '/' + AName, Virtual, CommandLine, WrapUntil) then
  begin
    Exit;
  end;
  Context := Default(TSlashContext);
  Context.Text := Virtual;
  Context.Line := CommandLine;
  Context.Name := AName;
  Context.Index := AIndex;
  if SameText(AName, 'ctor') then
  begin
    Result := CtorFields(Context);
  end
  else if SameText(AName, 'override') then
  begin
    Result := OverrideCandidates(Context);
  end
  else if SameText(AName, 'equals') then
  begin
    Result := EqualsFields(Context);
  end
  else if SameText(AName, 'encapsulate') then
  begin
    Result := EncapsulateFields(Context);
  end
  else if SameText(AName, 'sort') or SameText(AName, 'filter') then
  begin
    Result := CollectionChoices(Context, '');
  end;
end;

class function TSlashMenu.CurrentWord(const AArguments: string): string;
var
  Index: Integer;
begin
  Index := Length(AArguments);
  while (Index > 0) and not CharInSet(AArguments[Index], [' ', ',', ':', #9, '(', ';']) do
  begin
    Dec(Index);
  end;
  Result := Copy(AArguments, Index + 1, MaxInt);
end;

class function TSlashMenu.ArgumentKind(const AName, AArguments: string): TSlashArgumentKind;
var
  Words: Integer;
  Trimmed: string;
begin
  Trimmed := TrimLeft(AArguments);
  // Fertige Wörter vor dem angefangenen.
  Words := Length(Trim(Copy(Trimmed, 1, Length(Trimmed) - Length(CurrentWord(Trimmed)))).Split([' ', ','],
    TStringSplitOptions.ExcludeEmpty));
  Result := TSlashArgumentKind.None;
  if MatchText(AName, ['sort', 'filter']) then
  begin
    Result := TSlashArgumentKind.Collection;
  end
  else if MatchText(AName, ['uses', 'open']) then
  begin
    Result := TSlashArgumentKind.Units;
  end
  else if MatchText(AName, ['var', 'field', 'prop', 'list', 'future']) then
  begin
    // Erst der freie Name, hinter dem ":" der Typ.
    if Pos(':', Trimmed) > 0 then
    begin
      Result := TSlashArgumentKind.Types;
    end;
  end
  else if SameText(AName, 'helper') and (Words = 0) then
  begin
    Result := TSlashArgumentKind.Types;
  end
  else if SameText(AName, 'intf') then
  begin
    Result := TSlashArgumentKind.Interfaces;
  end
  else if MatchText(AName, ['raise', 'exception']) and (Words = 0) then
  begin
    Result := TSlashArgumentKind.Exceptions;
  end
  else if SameText(AName, 'override') then
  begin
    Result := TSlashArgumentKind.Overrides;
  end
  else if SameText(AName, 'ignore') and (Words = 0) then
  begin
    Result := TSlashArgumentKind.Rules;
  end;
end;

type
  TWantedKinds = set of TIndexSymbolKind;

/// <summary>Symbolarten, die zu AKind passen.</summary>
function WantedKinds(AKind: TSlashArgumentKind): TWantedKinds;
begin
  case AKind of
    TSlashArgumentKind.Interfaces:
      Result := [TIndexSymbolKind.InterfaceType];
    TSlashArgumentKind.Exceptions:
      Result := [TIndexSymbolKind.ClassType];
  else
    Result := [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
      TIndexSymbolKind.InterfaceType, TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias];
  end;
end;

/// <summary>Ist ASymbol ein Vorschlag zu AKind: auf Unit-Ebene, passende Art, beginnt mit APrefix; Ausnahmen mit
/// E-Präfix.</summary>
function IsChoice(const ASymbol: TIndexSymbol; AKind: TSlashArgumentKind; const AWanted: TWantedKinds;
  const APrefix: string): Boolean;
begin
  Result := (ASymbol.Container = '') and (ASymbol.Kind in AWanted) and StartsText(APrefix, ASymbol.Name);
  if Result and (AKind = TSlashArgumentKind.Exceptions) then
  begin
    Result := (Length(ASymbol.Name) > 1) and CharInSet(ASymbol.Name[1], ['E', 'e']);
  end;
end;

/// <summary>Hängt die Vorschläge aus AUnit zu AKind an ANames an: den Unit-Namen bei Units, sonst ihre
/// Typen.</summary>
procedure AddUnitChoices(ANames: TList<string>; const AUnit: TUnitIndex; AKind: TSlashArgumentKind;
  const AWanted: TWantedKinds; const APrefix: string);
var
  mSymbol: TIndexSymbol;
begin
  if AKind = TSlashArgumentKind.Units then
  begin
    if StartsText(APrefix, AUnit.UnitName) then
    begin
      ANames.Add(AUnit.UnitName);
    end;
    Exit;
  end;
  for mSymbol in AUnit.Symbols do
  begin
    if IsChoice(mSymbol, AKind, AWanted, APrefix) then
    begin
      ANames.Add(mSymbol.Name);
    end;
  end;
end;

/// <summary>ANames nach Namen sortiert, ohne doppelte, höchstens TSlashMenu.MaxChoices.</summary>
function SortedChoices(ANames: TList<string>): TArray<string>;
var
  mIndex: Integer;
begin
  ANames.Sort(TComparer<string>.Construct(
    function(const A, B: string): Integer
    begin
      Result := CompareText(A, B);
    end));
  Result := nil;
  for mIndex := 0 to ANames.Count - 1 do
  begin
    if Length(Result) >= TSlashMenu.MaxChoices then
    begin
      Break;
    end;
    if (Length(Result) = 0) or not SameText(Result[High(Result)], ANames[mIndex]) then
    begin
      Result := Result + [ANames[mIndex]];
    end;
  end;
end;

/// <summary>Namen aus AIndex auf Unit-Ebene zu AKind, die mit APrefix beginnen; nach Namen sortiert, ohne
/// doppelte, höchstens TSlashMenu.MaxChoices.</summary>
function IndexChoices(const AIndex: ISymbolIndex; AKind: TSlashArgumentKind; const APrefix: string): TArray<string>;
var
  mNames: TList<string>;
  mUnit: TUnitIndex;
  mWanted: TWantedKinds;
begin
  Result := nil;
  if AIndex = nil then
  begin
    Exit;
  end;
  mWanted := WantedKinds(AKind);
  mNames := TList<string>.Create;
  try
    for mUnit in AIndex.Units do
    begin
      AddUnitChoices(mNames, mUnit, AKind, mWanted, APrefix);
    end;
    Result := SortedChoices(mNames);
  finally
    mNames.Free;
  end;
end;

function Filtered(const AChoices: TArray<string>; const APrefix: string): TArray<string>;
var
  Choice: string;
begin
  Result := nil;
  for Choice in AChoices do
  begin
    if StartsText(APrefix, Choice) then
    begin
      Result := Result + [Choice];
    end;
  end;
end;

class function TSlashMenu.ArgumentChoices(const AText: string; ALine: Integer; const AName, AArguments: string;
  const AIndex: ISymbolIndex): TArray<string>;
begin
  Result := ArgumentChoices(AText, ALine, AName, AArguments, AIndex, nil);
end;

class function TSlashMenu.ArgumentChoices(const AText: string; ALine: Integer; const AName, AArguments: string;
  const AIndex: ISymbolIndex; const ARuleIds: TArray<string>): TArray<string>;
var
  Context: TSlashContext;
  Space: Integer;
  Kind: TSlashArgumentKind;
  Prefix: string;
begin
  Result := nil;
  Kind := ArgumentKind(AName, AArguments);
  if Kind = TSlashArgumentKind.None then
  begin
    Exit;
  end;
  Context := Default(TSlashContext);
  Context.Text := AText;
  Context.Line := ALine;
  Context.Name := AName;
  Context.Index := AIndex;
  Prefix := CurrentWord(AArguments);
  case Kind of
    TSlashArgumentKind.Collection:
      begin
        // Erst die Sammlung, nach dem Leerzeichen die Mitglieder ihres Elementtyps.
        Space := Pos(' ', TrimLeft(AArguments));
        if Space = 0 then
        begin
          Result := CollectionChoices(Context, '');
        end
        else
        begin
          Result := CollectionChoices(Context, Copy(TrimLeft(AArguments), 1, Space - 1));
        end;
      end;
    TSlashArgumentKind.Overrides:
      Result := Filtered(OverrideCandidates(Context), Prefix);
    TSlashArgumentKind.Rules:
      begin
        Result := Filtered(ARuleIds, Prefix);
        TArray.Sort<string>(Result);
      end;
  else
    Result := IndexChoices(AIndex, Kind, Prefix);
  end;
end;

class function TSlashMenu.Run(ARegistry: TSlashCommandRegistry; const AText: string; const ASpot: TSlashSpot;
  const ACall: TSlashMenuCall; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mVirtual, mCommand: string;
  mCommandLine, mWrapUntil: Integer;
  mEdits: TArray<TTextEdit>;
  mLines: TArray<string>;
begin
  AEdits := nil;
  AReason := '';
  mCommand := '/' + ACall.Name;
  if Trim(ACall.Arguments) <> '' then
  begin
    mCommand := mCommand + ' ' + Trim(ACall.Arguments);
  end;
  if not Prepare(AText, ASpot, mCommand, mVirtual, mCommandLine, mWrapUntil) then
  begin
    AReason := cTexts[TEditingSlashMenuText.TheCursorPositionLiesOutside].Text;
    Exit(False);
  end;
  Result := ARegistry.Run(mVirtual, mCommandLine, mWrapUntil, ACall.Environment, mEdits, AReason);
  if Result then
  begin
    mLines := TTextLines.SplitLines(mVirtual);
    AEdits := MapEdits(mEdits, mCommandLine, mLines[mCommandLine], TTextLines.LineBreakOf(AText));
  end;
end;

/// <summary>APosition im Text ohne die gedachte Zeile ACommandLine; Stellen in ihr rücken an ihren Anfang.</summary>
function MapPosition(const APosition: TTextPosition; ACommandLine: Integer): TTextPosition;
begin
  if APosition.Line < ACommandLine then
  begin
    Result := APosition;
  end
  else if APosition.Line = ACommandLine then
  begin
    Result := TTextPosition.Create(ACommandLine, 0);
  end
  else
  begin
    Result := TTextPosition.Create(APosition.Line - 1, APosition.Character);
  end;
end;

type
  /// <summary>Wie die Änderungen die gedachte Befehlszeile überdecken: erste Änderung in ihr (FirstEdit ab
  /// FirstStart, -1 ohne bzw. wenn eine Änderung von davor hineinreicht), letzte, die in ihr endet (LastEdit bis
  /// LastEnd), und ob eine Änderung ihr Zeilenende überdeckt.</summary>
  TCommandLineCover = record
    FirstStart: Integer;
    FirstEdit: Integer;
    LastEnd: Integer;
    LastEdit: Integer;
    BreakCovered: Boolean;
    procedure Consider(const AEdit: TTextEdit; AIndex, ACommandLine: Integer);
    procedure Scan(const AEdits: TArray<TTextEdit>; ACommandLine: Integer);
  end;

procedure TCommandLineCover.Consider(const AEdit: TTextEdit; AIndex, ACommandLine: Integer);
begin
  if (AEdit.Range.StartPos.Line <= ACommandLine) and (AEdit.Range.EndPos.Line > ACommandLine) then
  begin
    BreakCovered := True;
  end;
  if (AEdit.Range.StartPos.Line = ACommandLine) and (AEdit.Range.StartPos.Character < FirstStart) then
  begin
    FirstStart := AEdit.Range.StartPos.Character;
    FirstEdit := AIndex;
  end;
  if (AEdit.Range.StartPos.Line < ACommandLine) and (AEdit.Range.EndPos.Line >= ACommandLine) then
  begin
    FirstStart := 0;
    FirstEdit := -1;
  end;
  if (AEdit.Range.EndPos.Line = ACommandLine) and (AEdit.Range.EndPos.Character > LastEnd) then
  begin
    LastEnd := AEdit.Range.EndPos.Character;
    LastEdit := AIndex;
  end;
end;

procedure TCommandLineCover.Scan(const AEdits: TArray<TTextEdit>; ACommandLine: Integer);
var
  mIndex: Integer;
begin
  FirstStart := MaxInt;
  FirstEdit := -1;
  LastEnd := -1;
  LastEdit := -1;
  BreakCovered := False;
  for mIndex := 0 to High(AEdits) do
  begin
    Consider(AEdits[mIndex], mIndex, ACommandLine);
  end;
end;

class function TSlashMenu.MapEdits(const AEdits: TArray<TTextEdit>; ACommandLine: Integer; const ACommandText,
  ALineBreak: string): TArray<TTextEdit>;
var
  mCover: TCommandLineCover;
  mEdit: TTextEdit;
  mIndex: Integer;
  mIndent: string;
begin
  // Was von der gedachten Zeile nicht überdeckt wird, bleibt im gedachten Ergebnis stehen: der Anfang vor der
  // ersten Änderung in der Zeile und ihr Zeilenende, wenn keine Änderung darüber hinausreicht.
  mCover.Scan(AEdits, ACommandLine);
  // Nur die Einrückung vor dem Befehl kann stehen bleiben, nie der Befehl selbst.
  mIndent := '';
  if (mCover.FirstEdit >= 0) and (mCover.FirstStart > 0) then
  begin
    mIndent := Copy(ACommandText, 1, Min(mCover.FirstStart, Length(TTextLines.IndentOf(ACommandText))));
  end;
  Result := nil;
  for mIndex := 0 to High(AEdits) do
  begin
    mEdit := TTextEdit.Create(TTextRange.Create(MapPosition(AEdits[mIndex].Range.StartPos, ACommandLine),
      MapPosition(AEdits[mIndex].Range.EndPos, ACommandLine)), AEdits[mIndex].NewText);
    if mIndex = mCover.FirstEdit then
    begin
      mEdit.NewText := mIndent + mEdit.NewText;
    end;
    if (mIndex = mCover.LastEdit) and not mCover.BreakCovered then
    begin
      mEdit.NewText := mEdit.NewText + ALineBreak;
    end;
    if not ((mEdit.Range.StartPos = mEdit.Range.EndPos) and (mEdit.NewText = '')) then
    begin
      Result := Result + [mEdit];
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.SlashMenu', cTexts);

end.
