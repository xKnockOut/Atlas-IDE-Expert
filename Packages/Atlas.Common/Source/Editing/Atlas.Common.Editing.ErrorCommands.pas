unit Atlas.Common.Editing.ErrorCommands;

// Schnellbefehle zur Absicherung (#304) im Rahmen aus #293:
//   /guard [AName]       nil-Prüfungen für Objekt-, Interface- und Zeigerparameter am Anfang der Routine
//   /raise EKlasse Text  raise EKlasse.Create('Text') bzw. CreateFmt bei Platzhaltern; legt EKlasse bei Bedarf an
// /exception steht bei den Typbefehlen, /except bei den Umschließen-Befehlen.

interface

uses
  Atlas.Common.Editing.Contract;

/// <summary>Trägt die Befehle zur Absicherung über ARegister ein.</summary>
procedure RegisterErrorCommands(const ARegister: TSlashRegister);

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
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.ClassCommands,
  Atlas.Common.Editing.CommandSource;

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
  begin
    Exit;
  end;
  for Group in Copy(ASignature, Open + 1, Close - Open - 1).Split([';']) do
  begin
    Colon := Pos(':', Group);
    if Colon = 0 then
    begin
      Continue;
    end;
    Names := Trim(Copy(Group, 1, Colon - 1));
    TypeName := Trim(Copy(Group, Colon + 1, MaxInt));
    // Standardwert abschneiden.
    if Pos('=', TypeName) > 0 then
    begin
      TypeName := Trim(Copy(TypeName, 1, Pos('=', TypeName) - 1));
    end;
    if StartsText('const ', Names) or StartsText('var ', Names) or StartsText('out ', Names) or
      StartsText('constref ', Names) then
    begin
      Names := Trim(Copy(Names, Pos(' ', Names) + 1, MaxInt));
    end;
    for Name in Names.Split([',']) do
    begin
      if Trim(Name) <> '' then
      begin
        Parameter.Name := Trim(Name);
        Parameter.TypeName := TypeName;
        Result := Result + [Parameter];
      end;
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
  begin
    Exit(False);
  end;
  if SameText(ATypeName, 'Pointer') or SameText(ATypeName, 'IInterface') or SameText(ATypeName, 'TObject') then
  begin
    Exit(True);
  end;
  for Symbol in ASource.UnitIndex.Symbols do
  begin
    if SameText(Symbol.Name, ATypeName) and (Symbol.Container = '') then
    begin
      Exit(Symbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType]);
    end;
  end;
  if AIndex <> nil then
  begin
    for Location in AIndex.FindSymbols(ATypeName) do
    begin
      if Location.Symbol.Container = '' then
      begin
        Exit(Location.Symbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType]);
      end;
    end;
  end;
  // Unbekannt: nach Namenskonvention.
  Result := CharInSet(ATypeName[1], ['T', 'I', 'P']) and CharInSet(ATypeName[2], ['A'..'Z']);
end;

/// <summary>Edit, das System.SysUtils ins uses des Abschnitts an ALine einträgt; False, wenn es schon da ist.</summary>
function AddSysUtils(ASource: TCommandSource; const AContext: TSlashContext; ALine: Integer;
  out AEdit: TTextEdit): Boolean;
begin
  Result := not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(ASource.Tree.Tokens), 'System.SysUtils',
    AContext.Namespaces) and TUsesClauses.AddUnit(ASource.Tree.Tokens, ASource.Offset(ALine), 'System.SysUtils',
    ASource.LineBreak, AEdit);
end;

{ /guard }

/// <summary>Zeilen AFirst..ALast, mit Leerzeichen verbunden.</summary>
function HeaderText(ASource: TCommandSource; AFirst, ALast: Integer): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := AFirst to ALast do
  begin
    Result := Result + ' ' + ASource.Lines[mIndex];
  end;
end;

/// <summary>Rumpf ABlock in Kleinbuchstaben ohne Leerzeichen, für die Suche nach vorhandenen Prüfungen.</summary>
function CompactBody(ASource: TCommandSource; ABlock: TSyntaxNode): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := ABlock.StartPos.Line to ABlock.EndPos.Line do
  begin
    Result := Result + ' ' + LowerCase(StringReplace(ASource.Lines[mIndex], ' ', '', [rfReplaceAll]));
  end;
end;

/// <summary>Braucht AParameter eine Prüfung: gewählt (oder kein Name angegeben), kann nil sein und wird im Rumpf
/// ABody noch nicht geprüft?</summary>
function NeedsGuard(ASource: TCommandSource; const AContext: TSlashContext; const AParameter: TGuardParameter;
  const ABody: string): Boolean;
var
  mName: string;
begin
  mName := LowerCase(AParameter.Name);
  Result := ((AContext.Arguments = '') or SameText(AParameter.Name, AContext.Arguments)) and
    IsNilable(ASource, AContext.Index, AParameter.TypeName) and (Pos('assigned(' + mName + ')', ABody) = 0) and
    (Pos(mName + '=nil', ABody) = 0);
end;

/// <summary>Prüfzeilen für alle Parameter der Routine, die eine brauchen; '' ohne.</summary>
function GuardChecks(ASource: TCommandSource; const AContext: TSlashContext; ARoutine, ABlock: TSyntaxNode): string;
var
  mBody, mIndent: string;
  mParameter: TGuardParameter;
begin
  Result := '';
  mBody := CompactBody(ASource, ABlock);
  mIndent := ASource.Indent(ABlock.StartPos.Line) + '  ';
  for mParameter in RoutineParameters(RoutineSignature(HeaderText(ASource, ARoutine.StartPos.Line,
    ABlock.StartPos.Line - 1))) do
  begin
    if not NeedsGuard(ASource, AContext, mParameter, mBody) then
    begin
      Continue;
    end;
    if Result <> '' then
    begin
      Result := Result + ASource.LineBreak;
    end;
    Result := Result + mIndent + Format('if not Assigned(%s) then', [mParameter.Name]) + ASource.LineBreak +
      mIndent + Format('  raise EArgumentNilException.Create(%s);', [QuotedStr(mParameter.Name)]);
  end;
end;

function NoGuardReason(const AArguments: string): string;
begin
  Result := 'Keine ungeprüften Objekt-, Interface- oder Zeigerparameter';
  if AArguments <> '' then
  begin
    Result := AArguments + ' ist kein ungeprüfter Objekt-, Interface- oder Zeigerparameter';
  end;
end;

function ExecuteGuard(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mRoutine, mBlock: TSyntaxNode;
  mChecks: string;
  mUsesEdit: TTextEdit;
begin
  AEdits := nil;
  if (AContext.Arguments <> '') and not IsValidIdent(AContext.Arguments) then
  begin
    Exit(Fail('Erwartet wird /guard [Parametername]', AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    mRoutine := mSource.RoutineAt;
    if mRoutine = nil then
    begin
      Exit(Fail('/guard gilt nur im Rumpf einer Routine', AReason));
    end;
    mBlock := mRoutine.FindChild(TSyntaxKind.Block);
    mChecks := GuardChecks(mSource, AContext, mRoutine, mBlock);
    if mChecks = '' then
    begin
      Exit(Fail(NoGuardReason(AContext.Arguments), AReason));
    end;
    AEdits := [mSource.AfterLine(mBlock.StartPos.Line, mChecks), mSource.RemoveCommand];
    if AddSysUtils(mSource, AContext, mRoutine.StartPos.Line, mUsesEdit) then
    begin
      AEdits := AEdits + [mUsesEdit];
    end;
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /raise }

function IsKnownException(ASource: TCommandSource; const AIndex: ISymbolIndex; const AName: string): Boolean;
var
  Symbol: TIndexSymbol;
begin
  if MatchText(AName, KnownExceptions) then
  begin
    Exit(True);
  end;
  for Symbol in ASource.UnitIndex.Symbols do
  begin
    if SameText(Symbol.Name, AName) and (Symbol.Kind = TIndexSymbolKind.ClassType) then
    begin
      Exit(True);
    end;
  end;
  Result := (AIndex <> nil) and (Length(AIndex.FindSymbols(AName)) > 0);
end;

function ExecuteRaise(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Routine: TSyntaxNode;
  Space: Integer;
  Name, Message, Statement: string;
  UsesEdit: TTextEdit;
begin
  AEdits := nil;
  Space := Pos(' ', AContext.Arguments);
  if Space = 0 then
  begin
    Space := Length(AContext.Arguments) + 1;
  end;
  Name := Copy(AContext.Arguments, 1, Space - 1);
  Message := Trim(Copy(AContext.Arguments, Space + 1, MaxInt));
  if not IsValidIdent(Name, True) or (Message = '') then
  begin
    Exit(Fail('Erwartet wird /raise EKlasse Text', AReason));
  end;
  Source := TCommandSource.Create(AContext);
  try
    Routine := Source.RoutineAt;
    if Routine = nil then
    begin
      Exit(Fail('/raise gilt nur im Rumpf einer Routine', AReason));
    end;
    if Pos('%', Message) > 0 then
    begin
      Statement := Format('raise %s.CreateFmt(%s, []);', [Name, QuotedStr(Message)]);
    end
    else
    begin
      Statement := Format('raise %s.Create(%s);', [Name, QuotedStr(Message)]);
    end;
    AEdits := [TTextEdit.Create(TTextRange.Create(Source.Line, 0, Source.Line + 1, 0),
      Source.Indent(Source.Line) + Statement + Source.LineBreak)];
    // Unbekannte Klasse vor der Routine anlegen.
    if not IsKnownException(Source, AContext.Index, Name) then
    begin
      AEdits := AEdits + [Source.BeforeLine(Routine.StartPos.Line, 'type' + Source.LineBreak +
        Format('  %s = class(Exception);', [Name]) + Source.LineBreak)];
    end;
    if AddSysUtils(Source, AContext, Routine.StartPos.Line, UsesEdit) then
    begin
      AEdits := AEdits + [UsesEdit];
    end;
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

procedure RegisterErrorCommands(const ARegister: TSlashRegister);
begin
  ARegister(Command('guard', 'nil-Prüfungen für Parameter einfügen', '/guard AKunde', ExecuteGuard));
  ARegister(Command('raise', 'Ausnahme auslösen', '/raise EImportFehler Datei fehlt', ExecuteRaise));
end;

end.
