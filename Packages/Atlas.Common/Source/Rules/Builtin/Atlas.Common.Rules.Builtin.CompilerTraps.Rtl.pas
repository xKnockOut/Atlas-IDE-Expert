unit Atlas.Common.Rules.Builtin.CompilerTraps.Rtl;

// Lücken der Delphi-RTL, die Free Pascal nicht hat (#2309, Gruppe Compiler vorab); FPC übersetzt die Fälle:
//   winapi-declaration-missing Die Unit bindet Winapi.Windows (bzw. Windows) ein und nennt einen Namen, den FPCs
//                              Windows deklariert, Delphis Winapi.Windows aber nicht (OpenThread,
//                              THREAD_SUSPEND_RESUME, PROCESS_QUERY_LIMITED_INFORMATION, ERROR_NOT_FOUND …; wie E2003).
//                              Still, wenn die Datei den Namen selbst deklariert oder die Namensauflösung ihn in
//                              einer anderen Unit als FPCs Windows findet (Delphis Quellen im Index). Je Name eine
//                              Meldung; sie nennt die Deklaration, die die Unit selbst anlegen muss.
//   winapi-uses-missing        Eine Routine, die Delphi nur in Winapi.Windows deklariert, FPC aber auch in SysUtils
//                              (GetTickCount64, GetTickCount, MulDiv), steht ohne Winapi.Windows in uses (wie
//                              E2003). TThread.GetTickCount64 und Namen hinter einem Punkt zählen nicht. Eine
//                              Meldung je Datei. Korrektur: Winapi.Windows in uses aufnehmen.
//   stream-write-nativeint     Eine Klasse überschreibt Write(const Buffer; Count: Longint): Longint von TStream,
//                              aber nicht die Überladung Write(const Buffer; Count: NativeInt): NativeInt, die es ab
//                              Delphi 13 gibt. WriteBuffer und CopyFrom rufen unter Win64 diese Überladung auf und
//                              gehen an der eigenen Fassung vorbei (still, ohne Compilermeldung). Gesucht wird die
//                              zweite Fassung im ganzen Text der Klasse, auch in {$IF}-Zweigen. Still bei
//                              eingestellter Delphi-Version vor 13.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cWinapiDeclarationMissingRuleId = 'winapi-declaration-missing';
  cWinapiUsesMissingRuleId = 'winapi-uses-missing';
  cStreamWriteNativeIntRuleId = 'stream-write-nativeint';

type
  TWinapiDeclarationMissingRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TWinapiUsesMissingRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TStreamWriteNativeIntRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Meldet die drei Regeln in ARegistry an.</summary>
procedure RegisterCompilerTrapRtlRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Semantics.NameResolver.Symbols,
  Atlas.Common.Rules.TypedScope,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen.</summary>
  TRtlTrapText = (DeclarationTitle, DeclarationMessage, UsesTitle, UsesMessage, UsesFix, StreamTitle,
    StreamMessage);

const
  cTexts: array[TRtlTrapText] of TAtlasText = (
    (De: 'Fehlt in Delphis Winapi.Windows'; En: 'Missing from Delphi''s Winapi.Windows'),
    (De: '%s steht in Free Pascals Windows, in Delphis Winapi.Windows aber nicht (wie E2003). Selbst ' +
      'deklarieren: %s';
     En: '%s is declared in Free Pascal''s Windows unit but not in Delphi''s Winapi.Windows (like E2003). ' +
      'Declare it yourself: %s'),
    (De: 'Winapi.Windows fehlt in uses'; En: 'Winapi.Windows missing from uses'),
    (De: '%s deklariert Delphi nur in Winapi.Windows, das hier nicht in uses steht; Free Pascal findet es auch ' +
      'in SysUtils (wie E2003). Winapi.Windows einbinden.';
     En: 'Delphi declares %s only in Winapi.Windows, which is not in uses here; Free Pascal also finds it in ' +
      'SysUtils (like E2003). Use Winapi.Windows.'),
    (De: 'Winapi.Windows in uses aufnehmen'; En: 'Add Winapi.Windows to uses'),
    (De: 'Write ohne NativeInt-Überladung'; En: 'Write without NativeInt overload'),
    (De: '%s überschreibt nur Write(...; Count: Longint). Ab Delphi 13 rufen WriteBuffer und CopyFrom unter ' +
      'Win64 Write(const Buffer; Count: NativeInt): NativeInt auf und gehen an dieser Fassung vorbei. Die ' +
      'NativeInt-Fassung ebenfalls überschreiben, in {$IF RTLVersion >= 37.0} und ' +
      '{$IF SizeOf(Longint) <> SizeOf(NativeInt)}.';
     En: '%s only overrides Write(...; Count: Longint). From Delphi 13 on, WriteBuffer and CopyFrom call ' +
      'Write(const Buffer; Count: NativeInt): NativeInt under Win64 and bypass this version. Override the ' +
      'NativeInt version as well, inside {$IF RTLVersion >= 37.0} and {$IF SizeOf(Longint) <> SizeOf(NativeInt)}.'));

{$SCOPEDENUMS OFF}

const
  cWindowsUnits: array[0..1] of string = ('Winapi.Windows', 'Windows');
  // Name|Deklaration: in FPCs Windows vorhanden, in Delphis Winapi.Windows nicht (Delphi-13-Bau).
  cMissingDeclarations: array[0..5] of string = (
    'OpenThread|function OpenThread(dwDesiredAccess: DWORD; bInheritHandle: BOOL; dwThreadId: DWORD): THandle; ' +
      'stdcall; external kernel32 name ''OpenThread'';',
    'THREAD_SUSPEND_RESUME|const THREAD_SUSPEND_RESUME = $0002;',
    'THREAD_GET_CONTEXT|const THREAD_GET_CONTEXT = $0008;',
    'THREAD_QUERY_INFORMATION|const THREAD_QUERY_INFORMATION = $0040;',
    'PROCESS_QUERY_LIMITED_INFORMATION|const PROCESS_QUERY_LIMITED_INFORMATION = $1000;',
    'ERROR_NOT_FOUND|const ERROR_NOT_FOUND = 1168;');
  // Routinen, die Delphi nur in Winapi.Windows deklariert, FPC auch in SysUtils.
  cWindowsOnlyRoutines: array[0..2] of string = ('GetTickCount64', 'GetTickCount', 'MulDiv');
  // Units von Free Pascal, deren Deklarationen in Delphi nicht gelten: Findet die Namensauflösung einen Namen nur
  // dort (FPC-Quellen im Index), bleibt der Befund.
  cFpcHomes: array[0..4] of string = ('Windows', 'SysUtils', 'ObjPas', 'Types', 'Math');
  cDelphi13 = '37.0';

/// <summary>Letzter Namensteil: TKlasse.Methode ergibt Methode.</summary>
function LastPart(const AName: string): string;
begin
  Result := Trim(Copy(AName, LastDelimiter('.', AName) + 1, MaxInt));
end;

/// <summary>Deklariert die Datei AName selbst (Typ, Konstante, Variable, Routine, Feld, Parameter)?</summary>
function DeclaresName(ARoot: TSyntaxNode; const AName: string): Boolean;
var
  mFound: Boolean;
begin
  mFound := False;
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mName: string;
    begin
      Result := not mFound;
      if not (ANode.Kind in [TSyntaxKind.TypeDecl, TSyntaxKind.ConstDecl, TSyntaxKind.VarDecl,
        TSyntaxKind.RoutineHeader, TSyntaxKind.Field, TSyntaxKind.Parameter, TSyntaxKind.InlineVar,
        TSyntaxKind.InlineConst]) then
      begin
        Exit;
      end;
      for mName in ANode.Name.Split([',']) do
      begin
        mFound := mFound or SameText(LastPart(mName), AName);
      end;
    end);
  Result := mFound;
end;

/// <summary>Steht vor dem Token AIndex (ohne Kommentare) ein Punkt?</summary>
function AfterDot(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  mBefore: Integer;
begin
  mBefore := AIndex - 1;
  while (mBefore >= 0) and (ATokens[mBefore].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Dec(mBefore);
  end;
  Result := (mBefore >= 0) and ATokens[mBefore].IsSymbol('.');
end;

/// <summary>Indizes der ersten Tokens je Name aus ANames, ohne Punkt davor und außerhalb der uses-Listen.</summary>
function FirstMentions(const ATokens: TArray<TPascalToken>; const ANames: array of string): TArray<Integer>;
var
  mClauses: TArray<TUsesClauseInfo>;
  mSeen: TArray<string>;
  mIndex: Integer;
begin
  Result := nil;
  mSeen := nil;
  mClauses := TUsesClauses.Clauses(ATokens);
  for mIndex := 0 to High(ATokens) do
  begin
    if (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) and MatchText(ATokens[mIndex].Text, ANames) and
      not MatchText(ATokens[mIndex].Text, mSeen) and not AfterDot(ATokens, mIndex) and
      not TUsesClauses.InClause(ATokens, mClauses, ATokens[mIndex].Offset) then
    begin
      mSeen := mSeen + [ATokens[mIndex].Text];
      Result := Result + [mIndex];
    end;
  end;
end;

/// <summary>Deklariert die Datei oder (mit Index) eine Unit außerhalb der RTL von FPC den Namen am Token AIndex?
/// Dann gilt die Deklaration auch in Delphi.</summary>
function DeclaredForDelphi(const AContext: TRuleContext; AScope: TTypedScope; AIndex: Integer): Boolean;
var
  mSymbol: TResolvedSymbol;
begin
  Result := DeclaresName(AContext.Tree.Root, AScope.Tokens[AIndex].Text);
  if Result or (AContext.Index = nil) then
  begin
    Exit;
  end;
  mSymbol := AScope.Resolver.Resolve(AContext.Tree, AScope.FileName, AScope.Tokens[AIndex].StartPos);
  Result := (mSymbol.Kind <> TResolvedKind.None) and not MatchText(mSymbol.UnitName, cFpcHomes);
end;

/// <summary>Bindet die Datei Winapi.Windows bzw. Windows ein?</summary>
function UsesWindows(const AContext: TRuleContext): Boolean;
var
  mUsed: TArray<string>;
begin
  mUsed := TUsesClauses.UsedUnits(AContext.Tree.Tokens);
  Result := TUsesClauses.IsUsed(mUsed, cWindowsUnits[0], AContext.Namespaces) or
    TUsesClauses.IsUsed(mUsed, cWindowsUnits[1], AContext.Namespaces);
end;

/// <summary>Deklaration aus cMissingDeclarations für AName.</summary>
function MissingDeclaration(const AName: string): string;
var
  mEntry: string;
begin
  Result := '';
  for mEntry in cMissingDeclarations do
  begin
    if SameText(Copy(mEntry, 1, Pos('|', mEntry) - 1), AName) then
    begin
      Exit(Copy(mEntry, Pos('|', mEntry) + 1, MaxInt));
    end;
  end;
end;

/// <summary>Namen aus cMissingDeclarations.</summary>
function MissingNames: TArray<string>;
var
  mEntry: string;
begin
  Result := nil;
  for mEntry in cMissingDeclarations do
  begin
    Result := Result + [Copy(mEntry, 1, Pos('|', mEntry) - 1)];
  end;
end;

/// <summary>Bereich des Tokens AIndex.</summary>
function TokenRange(const ATokens: TArray<TPascalToken>; AIndex: Integer): TTextRange;
begin
  Result := TTextRange.Create(ATokens[AIndex].StartPos, ATokens[AIndex].EndPos);
end;

{ TWinapiDeclarationMissingRule }

function TWinapiDeclarationMissingRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cWinapiDeclarationMissingRuleId, TRuleSeverity.Error,
    cTexts[TRtlTrapText.DeclarationTitle].Text);
end;

procedure TWinapiDeclarationMissingRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScope: TTypedScope;
  mMentions: TArray<Integer>;
  mIndex: Integer;
  mName: string;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not UsesWindows(AContext) then
  begin
    Exit;
  end;
  mMentions := FirstMentions(AContext.Tree.Tokens, MissingNames);
  if mMentions = nil then
  begin
    Exit;
  end;
  mScope := TTypedScope.Create(AContext);
  try
    for mIndex in mMentions do
    begin
      if not DeclaredForDelphi(AContext, mScope, mIndex) then
      begin
        mName := mScope.Tokens[mIndex].Text;
        AReport.Add(TokenRange(mScope.Tokens, mIndex), cTexts[TRtlTrapText.DeclarationMessage].Fmt([mName,
          MissingDeclaration(mName)]), TRuleConfidence.High);
      end;
    end;
  finally
    mScope.Free;
  end;
end;

{ TWinapiUsesMissingRule }

function TWinapiUsesMissingRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cWinapiUsesMissingRuleId, TRuleSeverity.Error, cTexts[TRtlTrapText.UsesTitle].Text);
end;

/// <summary>Korrektur: Winapi.Windows ins uses des Abschnitts am Token AIndex; ohne, wenn es dort keine Liste gibt.
/// </summary>
function AddWindowsFixes(const AContext: TRuleContext; AIndex: Integer): TArray<TRuleFix>;
var
  mEdit: TTextEdit;
begin
  Result := nil;
  if TUsesClauses.AddUnit(AContext.Tree.Tokens, AContext.Tree.Tokens[AIndex].Offset, cWindowsUnits[0],
    TTextLines.LineBreakOf(AContext.Text), mEdit) then
  begin
    Result := [TRuleFix.Create(cTexts[TRtlTrapText.UsesFix].Text, [mEdit], False)];
  end;
end;

procedure TWinapiUsesMissingRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScope: TTypedScope;
  mMentions: TArray<Integer>;
  mIndex: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or UsesWindows(AContext) then
  begin
    Exit;
  end;
  mMentions := FirstMentions(AContext.Tree.Tokens, cWindowsOnlyRoutines);
  if mMentions = nil then
  begin
    Exit;
  end;
  mScope := TTypedScope.Create(AContext);
  try
    for mIndex in mMentions do
    begin
      if not DeclaredForDelphi(AContext, mScope, mIndex) then
      begin
        AReport.Add(TokenRange(mScope.Tokens, mIndex), cTexts[TRtlTrapText.UsesMessage].Fmt(
          [mScope.Tokens[mIndex].Text]), TRuleConfidence.High, AddWindowsFixes(AContext, mIndex));
        Exit;
      end;
    end;
  finally
    mScope.Free;
  end;
end;

{ TStreamWriteNativeIntRule }

function TStreamWriteNativeIntRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cStreamWriteNativeIntRuleId, TRuleSeverity.Warning,
    cTexts[TRtlTrapText.StreamTitle].Text);
end;

/// <summary>Hat der Kopf die Direktive AName?</summary>
function HasDirective(AHeader: TSyntaxNode; const AName: string): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to AHeader.ChildCount - 1 do
  begin
    if (AHeader[mIndex].Kind = TSyntaxKind.Directive) and SameText(AHeader[mIndex].Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Typname des ersten Typverweises unter ANode; '' ohne.</summary>
function TypeNameOf(ANode: TSyntaxNode): string;
var
  mType: TSyntaxNode;
begin
  Result := '';
  mType := ANode.FindChild(TSyntaxKind.TypeReference);
  if mType <> nil then
  begin
    Result := LastPart(mType.Name);
  end;
end;

/// <summary>Ist AHeader "function Write(const Buffer; Count: Longint): Longint; override"?</summary>
function IsLongintWriteOverride(AHeader: TSyntaxNode): Boolean;
var
  mParams: TSyntaxNode;
begin
  Result := False;
  if not SameText(LastPart(AHeader.Name), 'Write') or not HasDirective(AHeader, 'override') or
    not SameText(TypeNameOf(AHeader), 'Longint') then
  begin
    Exit;
  end;
  mParams := AHeader.FindChild(TSyntaxKind.Parameters);
  Result := (mParams <> nil) and (mParams.ChildCount = 2) and
    (mParams[0].Modifier = TParameterModifier.ConstParam) and (TypeNameOf(mParams[0]) = '') and
    SameText(TypeNameOf(mParams[1]), 'Longint');
end;

/// <summary>Text ohne Leerraum, in Kleinbuchstaben.</summary>
function Compact(const AText: string): string;
var
  mChar: Char;
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create(Length(AText));
  try
    for mChar in AText do
    begin
      if mChar > ' ' then
      begin
        mBuilder.Append(mChar);
      end;
    end;
    Result := LowerCase(mBuilder.ToString);
  finally
    mBuilder.Free;
  end;
end;

/// <summary>Ist der Text ab AStart (Kleinbuchstaben) ein ganzes Wort "write" mit der Parameterliste
/// "(const Buffer; Count: NativeInt)" bzw. Int64 dahinter?</summary>
function IsNativeIntWriteAt(const AText: string; AStart: Integer): Boolean;
var
  mClose: Integer;
  mParams: string;
begin
  Result := False;
  if (AStart > 1) and CharInSet(AText[AStart - 1], ['a'..'z', '0'..'9', '_']) then
  begin
    Exit;
  end;
  mClose := PosEx(')', AText, AStart);
  if mClose = 0 then
  begin
    Exit;
  end;
  mParams := Compact(Copy(AText, AStart, mClose - AStart));
  Result := StartsText('write(const', mParams) and (Pos(';', mParams) > 0) and
    (EndsText(':nativeint', mParams) or EndsText(':int64', mParams) or EndsText(':system.nativeint', mParams));
end;

/// <summary>Steht im Text der Klasse eine Write-Fassung mit NativeInt bzw. Int64 als Anzahl, auch in {$IF}-Zweigen?
/// </summary>
function HasNativeIntWrite(const AText: string; AClass: TSyntaxNode): Boolean;
var
  mText: string;
  mStart: Integer;
begin
  mText := LowerCase(Copy(AText, AClass.StartOffset + 1, AClass.EndOffset - AClass.StartOffset));
  mStart := Pos('write', mText);
  while mStart > 0 do
  begin
    if IsNativeIntWriteAt(mText, mStart) then
    begin
      Exit(True);
    end;
    mStart := PosEx('write', mText, mStart + 1);
  end;
  Result := False;
end;

/// <summary>Kopf der überschriebenen Longint-Fassung von Write in AClass; nil ohne.</summary>
function LongintWrite(AClass: TSyntaxNode): TSyntaxNode;
begin
  Result := AClass.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode <> AClass) and (ANode.Kind in [TSyntaxKind.ClassType, TSyntaxKind.RecordType]) then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if (ANode.Kind = TSyntaxKind.RoutineHeader) and IsLongintWriteOverride(ANode) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
end;

procedure TStreamWriteNativeIntRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'override') or
    not TLanguageFeatures.IsAtLeast(AContext.DelphiVersion, cDelphi13) then
  begin
    Exit;
  end;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mHeader: TSyntaxNode;
    begin
      Result := True;
      if ANode.Kind <> TSyntaxKind.ClassType then
      begin
        Exit;
      end;
      mHeader := LongintWrite(ANode);
      if (mHeader <> nil) and not HasNativeIntWrite(AContext.Text, ANode) then
      begin
        AReport.Add(TTextRange.Create(mHeader.StartPos, mHeader.EndPos), cTexts[TRtlTrapText.StreamMessage].Fmt(
          [ANode.EnclosingTypeName]), TRuleConfidence.High);
      end;
    end);
end;

procedure RegisterCompilerTrapRtlRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TWinapiDeclarationMissingRule.Create);
  ARegistry.Register(TWinapiUsesMissingRule.Create);
  ARegistry.Register(TStreamWriteNativeIntRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.CompilerTraps.Rtl', cTexts);

end.
