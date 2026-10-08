unit BDLsp.Common.Editing.ErrorCommands;

// Schnellbefehle zur Absicherung (#304) im Rahmen aus #293:
//   /guard [AName]       nil-Prüfungen für Objekt-, Interface- und Zeigerparameter am Anfang der Routine
//   /raise EKlasse Text  raise EKlasse.Create('Text') bzw. CreateFmt bei Platzhaltern; legt EKlasse bei Bedarf an
// /exception steht bei den Typbefehlen, /except bei den Umschließen-Befehlen.

interface

uses
  BDLsp.Common.Editing.SlashCommands;

/// <summary>Trägt die Befehle zur Absicherung in ARegistry ein.</summary>
procedure RegisterErrorCommands(ARegistry: TSlashCommandRegistry);

type
  TGuardParameter = record
    Name: string;
    TypeName: string;
  end;

/// <summary>Parameter aus einem Routinenkopf ("procedure P(const A: T; var B, C: U)").</summary>
function RoutineParameters(const ASignature: string): TArray<TGuardParameter>;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Editing.UsesClause,
  BDLsp.Common.Editing.ClassCommands,
  BDLsp.Common.Editing.CommandSource;

const
  // Typen mit T-Präfix, die keine Klassen sind.
  ValueTypes: array[0..13] of string = ('TDateTime', 'TDate', 'TTime', 'TColor', 'TPoint', 'TRect', 'TSize',
    'TGUID', 'TBytes', 'TValue', 'TFormatSettings', 'TPointF', 'TRectF', 'TAlphaColor');
  // Ausnahmen aus System.SysUtils und System.Classes.
  KnownExceptions: array[0..12] of string = ('Exception', 'EAbort', 'EArgumentException', 'EArgumentNilException',
    'EArgumentOutOfRangeException', 'EInvalidOperation', 'EConvertError', 'ENotSupportedException',
    'ENotImplemented', 'EInvalidArgument', 'EFileNotFoundException', 'EInvalidOpException', 'EListError');

function RoutineParameters(const ASignature: string): TArray<TGuardParameter>;
var
  Open, Close, Colon: Integer;
  Group, Names, TypeName, Name: string;
  Parameter: TGuardParameter;
begin
  Result := nil;
  Open := Pos('(', ASignature);
  Close := LastDelimiter(')', ASignature);
  if (Open = 0) or (Close < Open) then
    Exit;
  for Group in Copy(ASignature, Open + 1, Close - Open - 1).Split([';']) do
  begin
    Colon := Pos(':', Group);
    if Colon = 0 then
      Continue;
    Names := Trim(Copy(Group, 1, Colon - 1));
    TypeName := Trim(Copy(Group, Colon + 1, MaxInt));
    // Standardwert abschneiden.
    if Pos('=', TypeName) > 0 then
      TypeName := Trim(Copy(TypeName, 1, Pos('=', TypeName) - 1));
    if StartsText('const ', Names) or StartsText('var ', Names) or StartsText('out ', Names) or
      StartsText('constref ', Names) then
      Names := Trim(Copy(Names, Pos(' ', Names) + 1, MaxInt));
    for Name in Names.Split([',']) do
      if Trim(Name) <> '' then
      begin
        Parameter.Name := Trim(Name);
        Parameter.TypeName := TypeName;
        Result := Result + [Parameter];
      end;
  end;
end;

/// <summary>Kann der Typ nil sein? Klassen, Interfaces und Zeiger; Records, Aufzählungen und Ereignisse nicht.</summary>
function IsNilable(ASource: TCommandSource; const AIndex: ISymbolIndex; const ATypeName: string): Boolean;
var
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
begin
  if (Length(ATypeName) < 2) or (Pos('<', ATypeName) > 0) or MatchText(ATypeName, ValueTypes) or
    EndsText('Event', ATypeName) then
    Exit(False);
  if SameText(ATypeName, 'Pointer') or SameText(ATypeName, 'IInterface') or SameText(ATypeName, 'TObject') then
    Exit(True);
  for Symbol in ASource.UnitIndex.Symbols do
    if SameText(Symbol.Name, ATypeName) and (Symbol.Container = '') then
      Exit(Symbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType]);
  if AIndex <> nil then
    for Location in AIndex.FindSymbols(ATypeName) do
      if Location.Symbol.Container = '' then
        Exit(Location.Symbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType]);
  // Unbekannt: nach Namenskonvention.
  Result := CharInSet(ATypeName[1], ['T', 'I', 'P']) and CharInSet(ATypeName[2], ['A'..'Z']);
end;

/// <summary>Edit, das System.SysUtils ins uses des Abschnitts an ALine einträgt; False, wenn es schon da ist.</summary>
function AddSysUtils(ASource: TCommandSource; const AContext: TSlashContext; ALine: Integer;
  out AEdit: TRuleEdit): Boolean;
begin
  Result := not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(ASource.Tree.Tokens), 'System.SysUtils',
    AContext.Namespaces) and TUsesClauses.AddUnit(ASource.Tree.Tokens, ASource.Offset(ALine), 'System.SysUtils',
    ASource.LineBreak, AEdit);
end;

{ /guard }

function ExecuteGuard(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Routine, Block: TSyntaxNode;
  Header, Body, Checks, Indent: string;
  Parameter: TGuardParameter;
  Index: Integer;
  UsesEdit: TRuleEdit;
begin
  AEdits := nil;
  if (AContext.Arguments <> '') and not IsValidIdent(AContext.Arguments) then
    Exit(Fail('Erwartet wird /guard [Parametername]', AReason));
  Source := TCommandSource.Create(AContext);
  try
    Routine := Source.RoutineAt;
    if Routine = nil then
      Exit(Fail('/guard gilt nur im Rumpf einer Routine', AReason));
    Block := Routine.FindChild(TSyntaxKind.Block);
    Header := '';
    for Index := Routine.StartPos.Line to Block.StartPos.Line - 1 do
      Header := Header + ' ' + Source.Lines[Index];
    Body := '';
    for Index := Block.StartPos.Line to Block.EndPos.Line do
      Body := Body + ' ' + LowerCase(StringReplace(Source.Lines[Index], ' ', '', [rfReplaceAll]));
    Indent := Source.Indent(Block.StartPos.Line) + '  ';
    Checks := '';
    for Parameter in RoutineParameters(RoutineSignature(Header)) do
    begin
      if (AContext.Arguments <> '') and not SameText(Parameter.Name, AContext.Arguments) then
        Continue;
      if not IsNilable(Source, AContext.Index, Parameter.TypeName) then
        Continue;
      // Vorhandene Prüfung nicht verdoppeln.
      if (Pos('assigned(' + LowerCase(Parameter.Name) + ')', Body) > 0) or
        (Pos(LowerCase(Parameter.Name) + '=nil', Body) > 0) then
        Continue;
      if Checks <> '' then
        Checks := Checks + Source.LineBreak;
      Checks := Checks + Indent + Format('if not Assigned(%s) then', [Parameter.Name]) + Source.LineBreak + Indent +
        Format('  raise EArgumentNilException.Create(%s);', [QuotedStr(Parameter.Name)]);
    end;
    if Checks = '' then
    begin
      if AContext.Arguments <> '' then
        Exit(Fail(AContext.Arguments + ' ist kein ungeprüfter Objekt-, Interface- oder Zeigerparameter', AReason));
      Exit(Fail('Keine ungeprüften Objekt-, Interface- oder Zeigerparameter', AReason));
    end;
    AEdits := [Source.AfterLine(Block.StartPos.Line, Checks), Source.RemoveCommand];
    if AddSysUtils(Source, AContext, Routine.StartPos.Line, UsesEdit) then
      AEdits := AEdits + [UsesEdit];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /raise }

function IsKnownException(ASource: TCommandSource; const AIndex: ISymbolIndex; const AName: string): Boolean;
var
  Symbol: TIndexSymbol;
begin
  if MatchText(AName, KnownExceptions) then
    Exit(True);
  for Symbol in ASource.UnitIndex.Symbols do
    if SameText(Symbol.Name, AName) and (Symbol.Kind = TIndexSymbolKind.ClassType) then
      Exit(True);
  Result := (AIndex <> nil) and (Length(AIndex.FindSymbols(AName)) > 0);
end;

function ExecuteRaise(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Routine: TSyntaxNode;
  Space: Integer;
  Name, Message, Statement: string;
  UsesEdit: TRuleEdit;
begin
  AEdits := nil;
  Space := Pos(' ', AContext.Arguments);
  if Space = 0 then
    Space := Length(AContext.Arguments) + 1;
  Name := Copy(AContext.Arguments, 1, Space - 1);
  Message := Trim(Copy(AContext.Arguments, Space + 1, MaxInt));
  if not IsValidIdent(Name, True) or (Message = '') then
    Exit(Fail('Erwartet wird /raise EKlasse Text', AReason));
  Source := TCommandSource.Create(AContext);
  try
    Routine := Source.RoutineAt;
    if Routine = nil then
      Exit(Fail('/raise gilt nur im Rumpf einer Routine', AReason));
    if Pos('%', Message) > 0 then
      Statement := Format('raise %s.CreateFmt(%s, []);', [Name, QuotedStr(Message)])
    else
      Statement := Format('raise %s.Create(%s);', [Name, QuotedStr(Message)]);
    AEdits := [TRuleEdit.Create(TTextRange.Create(Source.Line, 0, Source.Line + 1, 0),
      Source.Indent(Source.Line) + Statement + Source.LineBreak)];
    // Unbekannte Klasse vor der Routine anlegen.
    if not IsKnownException(Source, AContext.Index, Name) then
      AEdits := AEdits + [Source.BeforeLine(Routine.StartPos.Line, 'type' + Source.LineBreak +
        Format('  %s = class(Exception);', [Name]) + Source.LineBreak)];
    if AddSysUtils(Source, AContext, Routine.StartPos.Line, UsesEdit) then
      AEdits := AEdits + [UsesEdit];
    Result := True;
  finally
    Source.Free;
  end;
end;

function Command(const AName, ASummary, AExample: string; const AExecute: TSlashExecute): TSlashCommand;
begin
  Result.Name := AName;
  Result.Summary := ASummary;
  Result.Example := AExample;
  Result.Execute := AExecute;
end;

procedure RegisterErrorCommands(ARegistry: TSlashCommandRegistry);
begin
  ARegistry.Register(Command('guard', 'nil-Prüfungen für Parameter einfügen', '/guard AKunde', ExecuteGuard));
  ARegistry.Register(Command('raise', 'Ausnahme auslösen', '/raise EImportFehler Datei fehlt', ExecuteRaise));
end;

end.
