unit Atlas.Common.Editing.WinApiCommands;

// Schnellbefehle für Windows-API und DLLs (#321) im Rahmen aus #293:
//   /external Name dll [delayed] [cdecl]  Importdeklaration; DLL-Name als Konstante,
//                                         wenn die Unit schon mehrere Importe daraus hat
//   /exports [Name]                       Routinen der library in die exports-Klausel
//   /oscheck                              Win32Check(…) bzw. "if … = 0 then RaiseLastOSError"
//   /olecheck                             OleCheck(…) um den COM-Aufruf darunter
// Der Rückgabetyp kommt aus der Unit, dem Symbolindex bzw. einer Liste
// bekannter API-Funktionen.

interface

uses
  Atlas.Common.Editing.Contract;

/// <summary>Trägt /external, /exports, /oscheck und /olecheck über ARegister ein.</summary>
procedure RegisterWinApiCommands(const ARegister: TSlashRegister);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TWinApiCommandsText = (ExpectedIsExternalNameDll, UnknownEntryAllowedAreDelayed, ExternalDoesNotBelongIn,
    ExternalNeedsAnImplementationSection, NoRoutineThatIsNot, ExportsClauseWithoutClosing, MainBlockOfTheLibrary,
    ExportsOnlyAppliesInA, OscheckOnlyAppliesInThe, BelowOscheckThereIsNo, ReturnTypeOfUnknownWin32Check,
    ReturnsNotBOOLWin32CheckDoes, OlecheckOnlyAppliesInThe, BelowOlecheckThereIsNo, ReturnsNotHRESULT,
    ImportAFunctionFromA, ExportRoutinesOfTheLibrary, CheckTheWindowsAPICall, CheckTheCOMCallBelow,
    WithoutCallingConventionStdcallCdecl, AllRoutinesAreAlreadyIn, Nothing, ExternalExample);

const
  cTexts: array[TWinApiCommandsText] of TAtlasText = (
    (De: 'Erwartet wird /external Name dll [delayed] [cdecl]';
     En: 'Expected is /external Name dll [delayed] [cdecl]'),
    (De: 'Unbekannte Angabe %s; erlaubt sind delayed und %s'; En: 'Unknown entry %s; allowed are delayed and %s'),
    (De: '/external gehört nicht in eine Klasse'; En: '/external does not belong in a class'),
    (De: '/external braucht hier einen implementation-Abschnitt';
     En: '/external needs an implementation section here'),
    (De: 'Keine Routine %s, die noch nicht exportiert wird'; En: 'No routine %s that is not exported yet'),
    (De: 'exports-Klausel ohne abschließendes ";"'; En: 'exports clause without closing ";"'),
    (De: 'Hauptblock der library nicht gefunden'; En: 'Main block of the library not found'),
    (De: '/exports gilt nur in einer library-Datei (.dpr)'; En: '/exports only applies in a library file (.dpr)'),
    (De: '/oscheck gilt nur im Rumpf einer Routine'; En: '/oscheck only applies in the body of a routine'),
    (De: 'Unter /oscheck steht kein Aufruf'; En: 'Below /oscheck there is no call'),
    (De: 'Rückgabetyp von %s unbekannt; Win32Check nur bei BOOL';
     En: 'Return type of %s unknown; Win32Check only for BOOL'),
    (De: '%s liefert %s, nicht BOOL; Win32Check passt nicht'; En: '%s returns %s, not BOOL; Win32Check does not fit'),
    (De: '/olecheck gilt nur im Rumpf einer Routine'; En: '/olecheck only applies in the body of a routine'),
    (De: 'Unter /olecheck steht kein Aufruf'; En: 'Below /olecheck there is no call'),
    (De: '%s liefert %s, nicht HRESULT'; En: '%s returns %s, not HRESULT'),
    (De: 'Funktion aus einer DLL importieren'; En: 'Import a function from a DLL'),
    (De: 'Routinen der library exportieren'; En: 'Export routines of the library'),
    (De: 'Windows-API-Aufruf darunter prüfen'; En: 'Check the Windows API call below'),
    (De: 'COM-Aufruf darunter mit OleCheck prüfen'; En: 'Check the COM call below with OleCheck'),
    (De: 'Ohne Aufrufkonvention (stdcall, cdecl): '; En: 'Without calling convention (stdcall, cdecl): '),
    (De: 'Alle Routinen stehen schon in exports'; En: 'All routines are already in exports'),
    (De: 'nichts'; En: 'nothing'),
    (De: '/external MeineFunktion meine.dll'; En: '/external MyFunction my.dll'));

{$SCOPEDENUMS OFF}

type
  TTokens = TArray<TPascalToken>;

const
  Conventions: array[0..5] of string = ('stdcall', 'cdecl', 'register', 'pascal', 'safecall', 'winapi');
  // Häufige Funktionen aus Winapi.Windows mit BOOL-Ergebnis, falls der Index sie nicht kennt.
  BoolFunctions: array[0..33] of string = ('CloseHandle', 'DeleteFile', 'CopyFile', 'MoveFile', 'MoveFileEx',
    'ReadFile', 'WriteFile', 'CreateDirectory', 'RemoveDirectory', 'SetEvent', 'ResetEvent', 'ReleaseMutex',
    'FreeLibrary', 'SetWindowPos', 'PostMessage', 'PostThreadMessage', 'DestroyWindow', 'SetCurrentDirectory',
    'GetExitCodeProcess', 'TerminateProcess', 'DuplicateHandle', 'FlushFileBuffers', 'SetEndOfFile', 'LockFile',
    'UnlockFile', 'GetFileTime', 'SetFileTime', 'GetComputerName', 'GetUserName', 'SystemParametersInfo',
    'SetFileAttributes', 'CreateProcess', 'ReleaseSemaphore', 'SetThreadPriority');
  BoolTypes: array[0..3] of string = ('BOOL', 'LongBool', 'Boolean', 'WordBool');

function IsCode(const AToken: TPascalToken): Boolean;
begin
  Result := not (AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]);
end;

{ /external }

/// <summary>Bezeichner aus dem DLL-Namen: meine.dll wird zu MeineDll.</summary>
function DllConstName(const ADll: string): string;
var
  C: Char;
  Upper: Boolean;
begin
  Result := '';
  Upper := True;
  for C in ChangeFileExt(ExtractFileName(ADll), '') do
  begin
    if CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9']) then
    begin
      if Upper then
      begin
        Result := Result + UpperCase(C);
      end
      else
      begin
        Result := Result + C;
      end;
      Upper := False;
    end
    else
    begin
      Upper := True;
    end;
  end;
  if (Result = '') or CharInSet(Result[1], ['0'..'9']) then
  begin
    Result := 'Lib' + Result;
  end;
  Result := Result + 'Dll';
end;

type
  /// <summary>Angaben von /external: Name, DLL, Aufrufkonvention und delayed.</summary>
  TExternalSpec = record
    Name: string;
    Dll: string;
    Convention: string;
    Delayed: Boolean;
  end;

/// <summary>AText ohne umschließende Hochkommas ('meine.dll' wird zu meine.dll).</summary>
function Unquoted(const AText: string): string;
begin
  Result := AText;
  if (Length(AText) >= 2) and (AText[1] = '''') and (AText[Length(AText)] = '''') then
  begin
    Result := Copy(AText, 2, Length(AText) - 2);
  end;
end;

/// <summary>Zerlegt die Argumente von /external; False mit Grund bei Fehlern.</summary>
function ParseExternal(const AArguments: string; out ASpec: TExternalSpec; out AReason: string): Boolean;
var
  mWords: TArray<string>;
  mIndex: Integer;
begin
  ASpec := Default(TExternalSpec);
  mWords := AArguments.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
  if (Length(mWords) < 2) or not IsValidIdent(mWords[0]) then
  begin
    Exit(Fail(cTexts[TWinApiCommandsText.ExpectedIsExternalNameDll].Text, AReason));
  end;
  ASpec.Name := mWords[0];
  ASpec.Dll := Unquoted(mWords[1]);
  ASpec.Convention := 'stdcall';
  for mIndex := 2 to High(mWords) do
  begin
    if SameText(mWords[mIndex], 'delayed') then
    begin
      ASpec.Delayed := True;
    end
    else if MatchText(mWords[mIndex], Conventions) then
    begin
      ASpec.Convention := LowerCase(mWords[mIndex]);
    end
    else
    begin
      Exit(Fail(cTexts[TWinApiCommandsText.UnknownEntryAllowedAreDelayed].Fmt([mWords[mIndex],
        string.Join(', ', Conventions)]), AReason));
    end;
  end;
  Result := True;
end;

/// <summary>Zahl der Importe "external 'ADll'" in der Unit.</summary>
function ImportCount(const ATokens: TTokens; const ADll: string): Integer;
var
  mIndex, mNext: Integer;
begin
  Result := 0;
  for mIndex := 0 to High(ATokens) - 1 do
  begin
    if not SameText(ATokens[mIndex].Text, 'external') then
    begin
      Continue;
    end;
    mNext := mIndex + 1;
    while (mNext <= High(ATokens)) and not IsCode(ATokens[mNext]) do
    begin
      Inc(mNext);
    end;
    if (mNext <= High(ATokens)) and SameText(ATokens[mNext].Text, QuotedStr(ADll)) then
    begin
      Inc(Result);
    end;
  end;
end;

/// <summary>Letzte globale Konstante der Unit, deren Zeile den DLL-Namen enthält; '' ohne.</summary>
function DllConstant(ASource: TCommandSource; const ADll: string): string;
var
  mConstant: TIndexSymbol;
begin
  Result := '';
  for mConstant in ASource.UnitIndex.Symbols do
  begin
    if (mConstant.Kind = TIndexSymbolKind.Constant) and (mConstant.Container = '') and
      ContainsText(ASource.Lines[mConstant.Range.StartPos.Line], QuotedStr(ADll)) then
    begin
      Result := mConstant.Name;
    end;
  end;
end;

/// <summary>Importdeklaration; ab zwei vorhandenen Importen aus derselben DLL steht ihr Name in einer (bei Bedarf
/// neuen) Konstante. Parameterliste und Ergebnis ergänzt der Entwickler; "()" hält sie übersetzbar.</summary>
function ExternalDeclaration(ASource: TCommandSource; const ASpec: TExternalSpec): string;
var
  mLibrary, mSuffix, mPrefix, mLineBreak: string;
begin
  mLineBreak := ASource.LineBreak;
  mLibrary := QuotedStr(ASpec.Dll);
  mPrefix := '';
  if ImportCount(ASource.Tree.Tokens, ASpec.Dll) >= 2 then
  begin
    mLibrary := DllConstant(ASource, ASpec.Dll);
    if mLibrary = '' then
    begin
      mLibrary := DllConstName(ASpec.Dll);
      mPrefix := 'const' + mLineBreak + Format('  %s = %s;', [mLibrary, QuotedStr(ASpec.Dll)]) + mLineBreak +
        mLineBreak;
    end;
  end;
  mSuffix := '';
  if ASpec.Delayed then
  begin
    mSuffix := ' delayed';
  end;
  Result := mPrefix + Format('procedure %s(); %s; external %s%s;', [ASpec.Name, ASpec.Convention, mLibrary,
    mSuffix]);
end;

function ExecuteExternal(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mSpec: TExternalSpec;
  mDeclaration, mIndent, mLineBreak: string;
  mClass: TIndexSymbol;
begin
  AEdits := nil;
  if not ParseExternal(AContext.Arguments, mSpec, AReason) then
  begin
    Exit(False);
  end;
  mSource := TCommandSource.Create(AContext);
  try
    if (mSource.RoutineAt = nil) and mSource.ClassAt(mClass) then
    begin
      Exit(Fail(cTexts[TWinApiCommandsText.ExternalDoesNotBelongIn].Text, AReason));
    end;
    mLineBreak := mSource.LineBreak;
    mDeclaration := ExternalDeclaration(mSource, mSpec);
    // Aus einer Routine heraus: in die implementation wie /const!.
    if (mSource.RoutineAt <> nil) and (mSource.ImplementationStart < 0) then
    begin
      Exit(Fail(cTexts[TWinApiCommandsText.ExternalNeedsAnImplementationSection].Text, AReason));
    end;
    if mSource.RoutineAt <> nil then
    begin
      AEdits := [mSource.AfterLine(mSource.ImplementationStart, mLineBreak + mDeclaration), mSource.RemoveCommand];
    end
    else
    begin
      mIndent := mSource.Indent(mSource.Line);
      AEdits := [TTextEdit.Create(TTextRange.Create(mSource.Line, 0, mSource.Line + 1, 0),
        mIndent + StringReplace(mDeclaration, mLineBreak, mLineBreak + mIndent, [rfReplaceAll]) + mLineBreak)];
    end;
    Result := True;
  finally
    mSource.Free;
  end;
end;

{ /exports }

function HasConvention(ARoutine: TSyntaxNode): Boolean;
var
  Header: TSyntaxNode;
  Index: Integer;
begin
  Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if Header = nil then
  begin
    Header := ARoutine;
  end;
  for Index := 0 to Header.ChildCount - 1 do
  begin
    if (Header[Index].Kind = TSyntaxKind.Directive) and MatchText(Header[Index].Name, Conventions) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Bezeichner, die in der exports-Klausel AClause schon stehen.</summary>
function ListedNames(ASource: TCommandSource; AClause: TSyntaxNode): TArray<string>;
var
  mToken: TPascalToken;
begin
  Result := nil;
  if AClause = nil then
  begin
    Exit;
  end;
  for mToken in ASource.Tree.Tokens do
  begin
    if (mToken.Kind = TPascalTokenKind.Identifier) and (mToken.StartPos.Line >= AClause.StartPos.Line) and
      (mToken.EndPos.Line <= AClause.EndPos.Line) then
    begin
      Result := Result + [mToken.Text];
    end;
  end;
end;

/// <summary>Ist ARoutine eine freie Routine, die AName heißt (alle bei leerem AName) und noch nicht in AListed
/// steht?</summary>
function IsExportCandidate(ARoutine: TSyntaxNode; const AName: string; const AListed: TArray<string>): Boolean;
begin
  Result := (ARoutine.Kind = TSyntaxKind.RoutineDecl) and (Pos('.', ARoutine.Name) = 0) and
    ((AName = '') or SameText(ARoutine.Name, AName)) and (IndexText(ARoutine.Name, AListed) < 0);
end;

/// <summary>Noch nicht exportierte Routinen der library: mit Aufrufkonvention in ANames, ohne in AMissing.</summary>
procedure CollectExports(ARoot: TSyntaxNode; const AName: string; const AListed: TArray<string>;
  out ANames, AMissing: TArray<string>);
var
  mIndex: Integer;
begin
  ANames := nil;
  AMissing := nil;
  for mIndex := 0 to ARoot.ChildCount - 1 do
  begin
    if not IsExportCandidate(ARoot[mIndex], AName, AListed) then
    begin
      Continue;
    end;
    if HasConvention(ARoot[mIndex]) then
    begin
      ANames := ANames + [ARoot[mIndex].Name];
    end
    else
    begin
      AMissing := AMissing + [ARoot[mIndex].Name];
    end;
  end;
end;

/// <summary>Grund, warum es nichts zu exportieren gibt.</summary>
function NothingToExport(const AMissing: TArray<string>; const AName: string): string;
begin
  if AMissing <> nil then
  begin
    Result := cTexts[TWinApiCommandsText.WithoutCallingConventionStdcallCdecl].Text + string.Join(', ', AMissing);
  end
  else if AName <> '' then
  begin
    Result := cTexts[TWinApiCommandsText.NoRoutineThatIsNot].Fmt([AName]);
  end
  else
  begin
    Result := cTexts[TWinApiCommandsText.AllRoutinesAreAlreadyIn].Text;
  end;
end;

/// <summary>Hängt AText vor das abschließende ";" der Klausel AClause; False ohne ";".</summary>
function AppendToClause(ASource: TCommandSource; AClause: TSyntaxNode; const AText: string;
  out AEdit: TTextEdit): Boolean;
var
  mToken: TPascalToken;
begin
  AEdit := Default(TTextEdit);
  Result := False;
  for mToken in ASource.Tree.Tokens do
  begin
    if mToken.IsSymbol(';') and (mToken.EndPos.Line = AClause.EndPos.Line) and
      (mToken.EndPos.Character = AClause.EndPos.Character) then
    begin
      AEdit := TTextEdit.Create(TTextRange.Create(mToken.StartPos, mToken.StartPos), AText);
      Result := True;
    end;
  end;
end;

/// <summary>Bearbeitung, die ANames in die exports-Klausel der library ARoot bringt (bzw. eine neue vor dem
/// Hauptblock); False mit Grund.</summary>
function ExportsEdit(ASource: TCommandSource; ARoot: TSyntaxNode; const ANames: TArray<string>;
  out AEdit: TTextEdit; out AReason: string): Boolean;
var
  mClause, mMain: TSyntaxNode;
  mName, mText: string;
begin
  AReason := '';
  mText := '';
  for mName in ANames do
  begin
    mText := mText + ',' + ASource.LineBreak + '  ' + mName;
  end;
  mClause := ARoot.FindChild(TSyntaxKind.ExportsClause);
  if mClause <> nil then
  begin
    Exit(AppendToClause(ASource, mClause, mText,
      AEdit) or Fail(cTexts[TWinApiCommandsText.ExportsClauseWithoutClosing].Text, AReason));
  end;
  mMain := ARoot.FindChild(TSyntaxKind.Block);
  if mMain = nil then
  begin
    AEdit := Default(TTextEdit);
    Exit(Fail(cTexts[TWinApiCommandsText.MainBlockOfTheLibrary].Text, AReason));
  end;
  AEdit := ASource.BeforeLine(mMain.StartPos.Line, 'exports' + Copy(mText, 2, MaxInt) + ';');
  Result := True;
end;

function ExecuteExports(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  mSource: TCommandSource;
  mRoot: TSyntaxNode;
  mNames, mMissing: TArray<string>;
  mEdit: TTextEdit;
begin
  AEdits := nil;
  mSource := TCommandSource.Create(AContext);
  try
    mRoot := mSource.Tree.Root;
    if (mRoot = nil) or (mRoot.Kind <> TSyntaxKind.LibraryFile) then
    begin
      Exit(Fail(cTexts[TWinApiCommandsText.ExportsOnlyAppliesInA].Text, AReason));
    end;
    CollectExports(mRoot, AContext.Arguments, ListedNames(mSource, mRoot.FindChild(TSyntaxKind.ExportsClause)),
      mNames, mMissing);
    if mNames = nil then
    begin
      Exit(Fail(NothingToExport(mMissing, AContext.Arguments), AReason));
    end;
    Result := ExportsEdit(mSource, mRoot, mNames, mEdit, AReason);
    if Result then
    begin
      AEdits := [mEdit, mSource.RemoveCommand];
    end;
  finally
    mSource.Free;
  end;
end;

{ /oscheck und /olecheck }

type
  TStatement = record
    /// <summary>Vom ersten Token bis vor das ";".</summary>
    Range: TTextRange;
    Text: string;
    /// <summary>Linke Seite bei einer Zuweisung, sonst ''.</summary>
    Target: string;
    /// <summary>Aufgerufene Routine (letzter Name vor der Klammer).</summary>
    Callee: string;
  end;

/// <summary>Erstes Code-Token hinter Zeile ALine; -1 ohne.</summary>
function FirstCodeBelow(const ATokens: TTokens; ALine: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ATokens) do
  begin
    if (ATokens[mIndex].StartPos.Line > ALine) and IsCode(ATokens[mIndex]) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Beendet AToken auf oberster Ebene eine Anweisung?</summary>
function EndsStatement(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsSymbol(';') or AToken.IsKeyword('end') or AToken.IsKeyword('else') or
    AToken.IsKeyword('until') or AToken.IsKeyword('begin');
end;

/// <summary>Index des Tokens, das die Anweisung ab AFirst beendet (über High ohne); AAssign: ":=" und AOpen: erste
/// "(" auf oberster Ebene, je -1 ohne.</summary>
function ScanStatement(const ATokens: TTokens; AFirst: Integer; out AAssign, AOpen: Integer): Integer;
var
  mDepth: Integer;
begin
  mDepth := 0;
  AAssign := -1;
  AOpen := -1;
  Result := AFirst;
  while Result <= High(ATokens) do
  begin
    if ATokens[Result].IsSymbol('(') or ATokens[Result].IsSymbol('[') then
    begin
      if (mDepth = 0) and (AOpen < 0) and ATokens[Result].IsSymbol('(') then
      begin
        AOpen := Result;
      end;
      Inc(mDepth);
    end
    else if ATokens[Result].IsSymbol(')') or ATokens[Result].IsSymbol(']') then
    begin
      Dec(mDepth);
    end
    else if (mDepth = 0) and ATokens[Result].IsSymbol(':=') then
    begin
      AAssign := Result;
    end
    else if (mDepth = 0) and EndsStatement(ATokens[Result]) then
    begin
      Break;
    end;
    Inc(Result);
  end;
end;

/// <summary>Text der Tokens AFirst bis ALast; mit Leerzeichen, wo im Quelltext Abstand war (ASpaced).</summary>
function TokenText(const ATokens: TTokens; AFirst, ALast: Integer; ASpaced: Boolean): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := AFirst to ALast do
  begin
    if ASpaced and (mIndex > AFirst) and ((ATokens[mIndex].StartPos.Line <> ATokens[mIndex - 1].EndPos.Line) or
      (ATokens[mIndex].StartPos.Character <> ATokens[mIndex - 1].EndPos.Character)) then
    begin
      Result := Result + ' ';
    end;
    Result := Result + ATokens[mIndex].Text;
  end;
end;

/// <summary>Anweisung unter der Befehlszeile; False ohne Aufruf.</summary>
function StatementBelow(ASource: TCommandSource; out AStatement: TStatement): Boolean;
var
  mTokens: TTokens;
  mFirst, mStop, mAssign, mOpen: Integer;
begin
  Result := False;
  mTokens := ASource.Tree.Tokens;
  mFirst := FirstCodeBelow(mTokens, ASource.Line);
  if (mFirst < 0) or (mTokens[mFirst].Kind <> TPascalTokenKind.Identifier) then
  begin
    Exit;
  end;
  mStop := ScanStatement(mTokens, mFirst, mAssign, mOpen);
  if (mStop > High(mTokens)) or not mTokens[mStop].IsSymbol(';') or (mOpen <= mFirst) or (mOpen < mAssign) then
  begin
    Exit;
  end;
  AStatement.Range := TTextRange.Create(mTokens[mFirst].StartPos, mTokens[mStop].StartPos);
  AStatement.Text := TokenText(mTokens, mFirst, mStop - 1, True);
  AStatement.Target := '';
  if mAssign >= 0 then
  begin
    AStatement.Target := TokenText(mTokens, mFirst, mAssign - 1, False);
  end;
  AStatement.Callee := mTokens[mOpen - 1].Text;
  Result := mTokens[mOpen - 1].Kind = TPascalTokenKind.Identifier;
end;

/// <summary>Rückgabetyp von AName aus Unit bzw. Index; '' wenn unbekannt.</summary>
function ResultType(ASource: TCommandSource; const AIndex: ISymbolIndex; const AName: string): string;
var
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
begin
  for Symbol in ASource.UnitIndex.Symbols do
  begin
    if (Symbol.Kind in [TIndexSymbolKind.Routine, TIndexSymbolKind.Method]) and SameText(Symbol.Name, AName) then
    begin
      Exit(IfThen(Symbol.TypeName = '', '-', Symbol.TypeName));
    end;
  end;
  if AIndex <> nil then
  begin
    for Location in AIndex.FindSymbols(AName) do
    begin
      if Location.Symbol.Kind in [TIndexSymbolKind.Routine, TIndexSymbolKind.Method] then
      begin
        Exit(IfThen(Location.Symbol.TypeName = '', '-', Location.Symbol.TypeName));
      end;
    end;
  end;
  if MatchText(AName, BoolFunctions) or MatchText(Copy(AName, 1, Length(AName) - 1), BoolFunctions) and
    CharInSet(AName[Length(AName)], ['A', 'W']) then
  begin
    Exit('BOOL');
  end;
  Result := '';
end;

/// <summary>Ersetzt Befehlszeile und Anweisung bzw. ergänzt danach eine Zeile.</summary>
function WrapStatement(ASource: TCommandSource; const AStatement: TStatement;
  const ANewText: string): TArray<TTextEdit>;
begin
  if AStatement.Range.StartPos.Line = ASource.Line + 1 then
  begin
    Result := [TTextEdit.Create(TTextRange.Create(TTextPosition.Create(ASource.Line, 0), AStatement.Range.EndPos),
      Copy(ASource.Lines[ASource.Line + 1], 1, AStatement.Range.StartPos.Character) + ANewText)];
  end
  else
  begin
    Result := [TTextEdit.Create(AStatement.Range, ANewText), ASource.RemoveCommand];
  end;
end;

function ExecuteOsCheck(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Statement: TStatement;
  TypeName, Condition, Indent: string;
  Line: Integer;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if Source.RoutineAt = nil then
    begin
      Exit(Fail(cTexts[TWinApiCommandsText.OscheckOnlyAppliesInThe].Text, AReason));
    end;
    if not StatementBelow(Source, Statement) then
    begin
      Exit(Fail(cTexts[TWinApiCommandsText.BelowOscheckThereIsNo].Text, AReason));
    end;
    TypeName := ResultType(Source, AContext.Index, Statement.Callee);
    if Statement.Target = '' then
    begin
      if TypeName = '' then
      begin
        Exit(Fail(cTexts[TWinApiCommandsText.ReturnTypeOfUnknownWin32Check].Fmt([Statement.Callee]), AReason));
      end;
      if not MatchText(TypeName, BoolTypes) then
      begin
        Exit(Fail(cTexts[TWinApiCommandsText.ReturnsNotBOOLWin32CheckDoes].Fmt([Statement.Callee,
          IfThen(TypeName = '-', cTexts[TWinApiCommandsText.Nothing].Text, TypeName)]), AReason));
      end;
      AEdits := WrapStatement(Source, Statement, 'Win32Check(' + Statement.Text + ')');
    end
    else
    begin
      // Rückgabewert genutzt: danach prüfen.
      if MatchText(TypeName, BoolTypes) then
      begin
        Condition := Format('not %s', [Statement.Target]);
      end
      else
      begin
        Condition := Format('%s = 0', [Statement.Target]);
      end;
      Line := Statement.Range.EndPos.Line;
      Indent := Source.Indent(Statement.Range.StartPos.Line);
      AEdits := [Source.AfterLine(Line, Format('%sif %s then', [Indent, Condition]) + Source.LineBreak + Indent +
        '  RaiseLastOSError;'), Source.RemoveCommand];
    end;
    AddUses(Source, AContext, Source.Line, ['System.SysUtils'], AEdits);
    Result := True;
  finally
    Source.Free;
  end;
end;

function ExecuteOleCheck(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Statement: TStatement;
  TypeName, Indent: string;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if Source.RoutineAt = nil then
    begin
      Exit(Fail(cTexts[TWinApiCommandsText.OlecheckOnlyAppliesInThe].Text, AReason));
    end;
    if not StatementBelow(Source, Statement) then
    begin
      Exit(Fail(cTexts[TWinApiCommandsText.BelowOlecheckThereIsNo].Text, AReason));
    end;
    TypeName := ResultType(Source, AContext.Index, Statement.Callee);
    if (TypeName <> '') and not MatchText(TypeName, ['HRESULT', 'HResult']) then
    begin
      Exit(Fail(cTexts[TWinApiCommandsText.ReturnsNotHRESULT].Fmt([Statement.Callee, IfThen(TypeName = '-',
        cTexts[TWinApiCommandsText.Nothing].Text,
        TypeName)]), AReason));
    end;
    if Statement.Target = '' then
    begin
      AEdits := WrapStatement(Source, Statement, 'OleCheck(' + Statement.Text + ')');
    end
    else
    begin
      Indent := Source.Indent(Statement.Range.StartPos.Line);
      AEdits := [Source.AfterLine(Statement.Range.EndPos.Line, Format('%sOleCheck(%s);', [Indent,
        Statement.Target])), Source.RemoveCommand];
    end;
    AddUses(Source, AContext, Source.Line, ['System.Win.ComObj'], AEdits);
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

procedure RegisterWinApiCommands(const ARegister: TSlashRegister);
begin
  ARegister(Command('external', cTexts[TWinApiCommandsText.ImportAFunctionFromA].Text,
    cTexts[TWinApiCommandsText.ExternalExample].Text,
    ExecuteExternal));
  ARegister(Command('exports', cTexts[TWinApiCommandsText.ExportRoutinesOfTheLibrary].Text, '/exports',
    ExecuteExports));
  ARegister(Command('oscheck', cTexts[TWinApiCommandsText.CheckTheWindowsAPICall].Text, '/oscheck', ExecuteOsCheck));
  ARegister(Command('olecheck', cTexts[TWinApiCommandsText.CheckTheCOMCallBelow].Text, '/olecheck', ExecuteOleCheck));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.WinApiCommands', cTexts);

end.
