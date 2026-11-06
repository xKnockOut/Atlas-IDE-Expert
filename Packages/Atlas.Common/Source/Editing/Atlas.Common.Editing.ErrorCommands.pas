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
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TErrorCommandsText = (NoUncheckedObjectInterfaceOr, IsNotAnUncheckedObject, ExpectedIsGuardParameterName,
    GuardOnlyAppliesInThe, ExpectedIsRaiseEClassText, RaiseOnlyAppliesInThe, InsertNilChecksForParameters,
    RaiseAnException, RaiseEImportErrorFileMissing, GuardACustomer);

const
  cTexts: array[TErrorCommandsText] of TAtlasText = (
    (De: 'Keine ungeprüften Objekt-, Interface- oder Zeigerparameter';
     En: 'No unchecked object, interface or pointer parameters'),
    (De: ' ist kein ungeprüfter Objekt-, Interface- oder Zeigerparameter';
     En: ' is not an unchecked object, interface or pointer parameter'),
    (De: 'Erwartet wird /guard [Parametername]'; En: 'Expected is /guard [ParameterName]'),
    (De: '/guard gilt nur im Rumpf einer Routine'; En: '/guard only applies in the body of a routine'),
    (De: 'Erwartet wird /raise EKlasse Text'; En: 'Expected is /raise EClass Text'),
    (De: '/raise gilt nur im Rumpf einer Routine'; En: '/raise only applies in the body of a routine'),
    (De: 'nil-Prüfungen für Parameter einfügen'; En: 'Insert nil checks for parameters'),
    (De: 'Ausnahme auslösen'; En: 'Raise an exception'),
    (De: '/raise EImportFehler Datei fehlt'; En: '/raise EImportError File missing'),
    (De: '/guard AKunde'; En: '/guard ACustomer'));

{$SCOPEDENUMS OFF}

const
  // Typen mit T-Präfix, die keine Klassen sind.
  cValueTypes: array[0..13] of string = ('TDateTime', 'TDate', 'TTime', 'TColor', 'TPoint', 'TRect', 'TSize',
    'TGUID', 'TBytes', 'TValue', 'TFormatSettings', 'TPointF', 'TRectF', 'TAlphaColor');
  // Ausnahmen aus System.SysUtils und System.Classes.
  cKnownExceptions: array[0..12] of string = ('Exception', 'EAbort', 'EArgumentException', 'EArgumentNilException',
    'EArgumentOutOfRangeException', 'EInvalidOperation', 'EConvertError', 'ENotSupportedException',
    'ENotImplemented', 'EInvalidArgument', 'EFileNotFoundException', 'EInvalidOpException', 'EListError');

function RoutineParameters(const ASignature: string): TArray<TGuardParameter>;
var
  mOpen, mClose, mColon: Integer;
  mGroup, mNames, mTypeName, mName: string;
  mParameter: TGuardParameter;
begin
  Result := nil;
  mOpen := Pos('(', ASignature);
  mClose := LastDelimiter(')', ASignature);
  if (mOpen = 0) or (mClose < mOpen) then
  begin
    Exit;
  end;
  for mGroup in Copy(ASignature, mOpen + 1, mClose - mOpen - 1).Split([';']) do
  begin
    mColon := Pos(':', mGroup);
    if mColon = 0 then
    begin
      Continue;
    end;
    mNames := Trim(Copy(mGroup, 1, mColon - 1));
    mTypeName := Trim(Copy(mGroup, mColon + 1, MaxInt));
    // Standardwert abschneiden.
    if Pos('=', mTypeName) > 0 then
    begin
      mTypeName := Trim(Copy(mTypeName, 1, Pos('=', mTypeName) - 1));
    end;
    if StartsText('const ', mNames) or StartsText('var ', mNames) or StartsText('out ', mNames) or
      StartsText('constref ', mNames) then
    begin
      mNames := Trim(Copy(mNames, Pos(' ', mNames) + 1, MaxInt));
    end;
    for mName in mNames.Split([',']) do
    begin
      if Trim(mName) <> '' then
      begin
        mParameter.Name := Trim(mName);
        mParameter.TypeName := mTypeName;
        Result := Result + [mParameter];
      end;
    end;
  end;
end;

/// <summary>Kann der Typ nil sein? Klassen, Interfaces und Zeiger; Records, Aufzählungen und Ereignisse
/// nicht.</summary>
function IsNilable(ASource: TCommandSource; const AIndex: ISymbolIndex; const ATypeName: string): Boolean;
var
  mSymbol: TIndexSymbol;
  mLocation: TSymbolLocation;
begin
  if (Length(ATypeName) < 2) or (Pos('<', ATypeName) > 0) or MatchText(ATypeName, cValueTypes) or
    EndsText('Event', ATypeName) then
  begin
    Exit(False);
  end;
  if SameText(ATypeName, 'Pointer') or SameText(ATypeName, 'IInterface') or SameText(ATypeName, 'TObject') then
  begin
    Exit(True);
  end;
  for mSymbol in ASource.UnitIndex.Symbols do
  begin
    if SameText(mSymbol.Name, ATypeName) and (mSymbol.Container = '') then
    begin
      Exit(mSymbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType]);
    end;
  end;
  if AIndex <> nil then
  begin
    for mLocation in AIndex.FindSymbols(ATypeName) do
    begin
      if mLocation.Symbol.Container = '' then
      begin
        Exit(mLocation.Symbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType]);
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
  Result := cTexts[TErrorCommandsText.NoUncheckedObjectInterfaceOr].Text;
  if AArguments <> '' then
  begin
    Result := AArguments + cTexts[TErrorCommandsText.IsNotAnUncheckedObject].Text;
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
    Exit(Fail(cTexts[TErrorCommandsText.ExpectedIsGuardParameterName].Text, AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    mRoutine := mSource.RoutineAt;
    if mRoutine = nil then
    begin
      Exit(Fail(cTexts[TErrorCommandsText.GuardOnlyAppliesInThe].Text, AReason));
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
  mSymbol: TIndexSymbol;
begin
  if MatchText(AName, cKnownExceptions) then
  begin
    Exit(True);
  end;
  for mSymbol in ASource.UnitIndex.Symbols do
  begin
    if SameText(mSymbol.Name, AName) and (mSymbol.Kind = TIndexSymbolKind.ClassType) then
    begin
      Exit(True);
    end;
  end;
  Result := (AIndex <> nil) and (Length(AIndex.FindSymbols(AName)) > 0);
end;

function ExecuteRaise(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mRoutine: TSyntaxNode;
  mSpace: Integer;
  mName, mMessage, mStatement: string;
  mUsesEdit: TTextEdit;
begin
  AEdits := nil;
  mSpace := Pos(' ', AContext.Arguments);
  if mSpace = 0 then
  begin
    mSpace := Length(AContext.Arguments) + 1;
  end;
  mName := Copy(AContext.Arguments, 1, mSpace - 1);
  mMessage := Trim(Copy(AContext.Arguments, mSpace + 1, MaxInt));
  if not IsValidIdent(mName, True) or (mMessage = '') then
  begin
    Exit(Fail(cTexts[TErrorCommandsText.ExpectedIsRaiseEClassText].Text, AReason));
  end;
  mSource := TCommandSource.Create(AContext);
  try
    mRoutine := mSource.RoutineAt;
    if mRoutine = nil then
    begin
      Exit(Fail(cTexts[TErrorCommandsText.RaiseOnlyAppliesInThe].Text, AReason));
    end;
    if Pos('%', mMessage) > 0 then
    begin
      mStatement := Format('raise %s.CreateFmt(%s, []);', [mName, QuotedStr(mMessage)]);
    end
    else
    begin
      mStatement := Format('raise %s.Create(%s);', [mName, QuotedStr(mMessage)]);
    end;
    AEdits := [TTextEdit.Create(TTextRange.Create(mSource.Line, 0, mSource.Line + 1, 0),
      mSource.Indent(mSource.Line) + mStatement + mSource.LineBreak)];
    // Unbekannte Klasse vor der Routine anlegen.
    if not IsKnownException(mSource, AContext.Index, mName) then
    begin
      AEdits := AEdits + [mSource.BeforeLine(mRoutine.StartPos.Line, 'type' + mSource.LineBreak +
        Format('  %s = class(Exception);', [mName]) + mSource.LineBreak)];
    end;
    if AddSysUtils(mSource, AContext, mRoutine.StartPos.Line, mUsesEdit) then
    begin
      AEdits := AEdits + [mUsesEdit];
    end;
    Result := True;
  finally
    mSource.Free;
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
  ARegister(Command('guard', cTexts[TErrorCommandsText.InsertNilChecksForParameters].Text,
    cTexts[TErrorCommandsText.GuardACustomer].Text,
    ExecuteGuard));
  ARegister(Command('raise', cTexts[TErrorCommandsText.RaiseAnException].Text,
    cTexts[TErrorCommandsText.RaiseEImportErrorFileMissing].Text, ExecuteRaise));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.ErrorCommands', cTexts);

end.
