unit Atlas.Common.Rules.Builtin.Migration.Unicode;

// Regeln für Code aus der Zeit vor Unicode (#117, Gruppe „Migration“). Seit Delphi 2009 ist Char ein WideChar
// (2 Byte) und string ein UnicodeString:
//   char-count-as-bytes
//                     Length(S) bzw. StrLen(P) als Byteanzahl: Move, FillChar, CopyMemory, MoveMemory,
//                     ZeroMemory, FillMemory, CompareMem, BlockRead/BlockWrite, ReadFile/WriteFile und die
//                     Stream-Methoden Read, ReadBuffer, Write, WriteBuffer mit einem Puffer aus demselben String
//                     (Move(S[1], Buf, Length(S)); auch PChar(S), Pointer(S)^, @S[1]); GetMem bzw. ReallocMem
//                     eines PChar mit Length(S) (+ 1). S ist sicher string, UnicodeString oder WideString, P sicher
//                     PChar bzw. PWideChar; Length(S) darf mit + bzw. - um eine Zahl verschoben sein. Es wird nur
//                     die Hälfte der Zeichen kopiert bzw. Speicher angelegt.
//                     Korrektur: (Length(S) …) * SizeOf(Char); nicht sicher, weil ein Ziel aus AnsiChar dann
//                     überläuft (die Meldung nennt das).
//   ansi-api-call     Aufruf einer …A-Funktion (MessageBoxA, CreateFileA …) mit PAnsiChar(AnsiString(S)) und S
//                     sicher string: Zeichen außerhalb der ANSI-Codepage gehen verloren. Korrektur: Funktion ohne A
//                     (MessageBox) und PChar(S); angeboten, wenn die Funktion nicht aufgelöst ist oder aus einer
//                     Winapi-Unit stammt und kein anderes Argument sicher ein Ansi-Typ ist.
// Nicht hier: Mischungen von AnsiString und string (string-conversion, W1057/W1058; die Regel schweigt, wenn
// Compilermeldungen vorliegen) und PChar auf AnsiString bzw. PAnsiChar auf string (suspicious-string-pointer-cast,
// W1044). Beide Regeln schweigen in inaktiven Zweigen und vor Delphi 2009; {$H-} schaltet sie ab.

interface

uses
  Atlas.Common.Rules.Contract;

const
  cCharCountAsBytesRuleId = 'char-count-as-bytes';
  cAnsiApiCallRuleId = 'ansi-api-call';

type
  TCharCountAsBytesRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Position des Arguments mit der Byteanzahl in einem Aufruf von ARoutine (0 = erstes Argument)
    /// und der Puffer, die aus dem String stammen müssen; -1 für andere Routinen. AMember: Aufruf als Methode
    /// (Stream.Write).</summary>
    class function CountArgument(const ARoutine: string; AMember: Boolean; out ABuffers: TArray<Integer>): Integer;
      static;
  end;

  TAnsiApiCallRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Name ohne das A einer Ansi-Funktion (MessageBoxA → MessageBox, lstrlenA → lstrlen); '' sonst.
    /// </summary>
    class function NeutralName(const AName: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.TypedScope,
  Atlas.Common.Rules.Builtin.Migration.Shared,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TMigrationUnicodeText = (CountTitle, CountCopies, CountAllocates, MultiplySize, ApiTitle, ApiLoses, UseNeutral);

const
  cTexts: array[TMigrationUnicodeText] of TAtlasText = (
    (De: 'Zeichenzahl als Byteanzahl'; En: 'Character count as byte count'),
    (De: '%s zählt Zeichen, %s erwartet Bytes; seit Delphi 2009 hat ein Char 2 Byte, es wird nur die Hälfte ' +
     'verarbeitet. Ist das Ziel ein AnsiChar-Puffer, braucht es eine Umwandlung statt der doppelten Größe.';
     En: '%s counts characters, %s expects bytes; since Delphi 2009 a Char has 2 bytes, only half is processed. ' +
     'If the target is an AnsiChar buffer, it needs a conversion instead of the doubled size.'),
    (De: '%s zählt Zeichen, %s legt Bytes an; für %s (%s) ist der Speicher halb so groß wie nötig.';
     En: '%s counts characters, %s allocates bytes; for %s (%s) the memory is half the size needed.'),
    (De: 'Mit SizeOf(Char) malnehmen'; En: 'Multiply by SizeOf(Char)'),
    (De: 'Ansi-Funktion mit umgewandeltem string'; En: 'Ansi function with converted string'),
    (De: '%s bekommt %s als AnsiString; Zeichen außerhalb der ANSI-Codepage gehen verloren. %s nimmt den string ' +
     'unverändert.';
     En: '%s gets %s as AnsiString; characters outside the ANSI code page are lost. %s takes the string unchanged.'),
    (De: '%s mit PChar verwenden'; En: 'Use %s with PChar'));

{$SCOPEDENUMS OFF}

function NodeRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

/// <summary>Alle Aufrufe unter ARoot in Quelltextreihenfolge, ohne Rekursion.</summary>
function CallsOf(ARoot: TSyntaxNode): TArray<TSyntaxNode>;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = TSyntaxKind.Call then
      begin
        Result := Result + [mNode];
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>Aufruf AName(X) mit genau einem Argument?</summary>
function IsCallOf(ANode: TSyntaxNode; const AName: string): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) and
    (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, AName);
end;

/// <summary>{$H-} bzw. {$LONGSTRINGS OFF} in der Datei: string ist dort ShortString.</summary>
function ShortStrings(const ATokens: TArray<TPascalToken>): Boolean;
var
  mToken: TPascalToken;
  mText: string;
begin
  Result := False;
  for mToken in ATokens do
  begin
    if mToken.Kind = TPascalTokenKind.Directive then
    begin
      mText := UpperCase(StringReplace(mToken.Text, ' ', '', [rfReplaceAll]));
      if ContainsStr(mText, '$H-') or ContainsStr(mText, ',H-') or ContainsStr(mText, '$LONGSTRINGSOFF') then
      begin
        Exit(True);
      end;
    end;
  end;
end;

/// <summary>Prüfung möglich: Baum vorhanden, Delphi ab 2009, kein ShortString.</summary>
function Applicable(const AContext: TRuleContext): Boolean;
begin
  Result := (AContext.Tree <> nil) and (AContext.Tree.Root <> nil) and
    TMigrationTypes.UnicodeAvailable(AContext.DelphiVersion) and not ShortStrings(AContext.Tree.Tokens);
end;

/// <summary>Deklarierter Typ (wie im Quelltext) der Variablen, des Felds oder Parameters ANode, wenn die
/// Deklaration sicher mit ANode übersetzt wird; PChar, PAnsiChar … hat die Namensauflösung nicht als Typ.</summary>
function DeclaredTypeName(AScope: TTypedScope; const AContext: TRuleContext; ANode: TSyntaxNode;
  out ATypeName: string): Boolean;
var
  mSymbol, mType: TResolvedSymbol;
  mTypeFound: Boolean;
begin
  ATypeName := '';
  Result := (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
    AScope.Resolver.NodeType(AContext.Tree, AScope.FileName, ANode, mSymbol, mType, mTypeFound) and
    AScope.DeclarationSure(mSymbol, ANode);
  if Result then
  begin
    ATypeName := Trim(mSymbol.TypeName);
  end;
end;

{ TCharCountAsBytesRule }

function TCharCountAsBytesRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cCharCountAsBytesRuleId, TRuleSeverity.Warning,
    cTexts[TMigrationUnicodeText.CountTitle].Text);
end;

class function TCharCountAsBytesRule.CountArgument(const ARoutine: string; AMember: Boolean;
  out ABuffers: TArray<Integer>): Integer;
begin
  Result := -1;
  ABuffers := nil;
  if AMember then
  begin
    if MatchText(ARoutine, ['Read', 'ReadBuffer', 'Write', 'WriteBuffer']) then
    begin
      ABuffers := [0];
      Result := 1;
    end;
  end
  else if MatchText(ARoutine, ['Move', 'CopyMemory', 'MoveMemory', 'CompareMem']) then
  begin
    ABuffers := [0, 1];
    Result := 2;
  end
  else if MatchText(ARoutine, ['FillChar', 'ZeroMemory', 'FillMemory']) then
  begin
    ABuffers := [0];
    Result := 1;
  end
  else if MatchText(ARoutine, ['BlockRead', 'BlockWrite', 'ReadFile', 'WriteFile']) then
  begin
    ABuffers := [1];
    Result := 2;
  end
  else if MatchText(ARoutine, ['GetMem', 'ReallocMem']) then
  begin
    // Kein Puffer aus dem String: Der Zeiger (erstes Argument) muss PChar sein.
    Result := 1;
  end;
end;

procedure TCharCountAsBytesRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScope: TTypedScope;
  mMigration: TMigrationScope;

  /// <summary>Length(S) bzw. StrLen(P) in ACount, auch mit + bzw. - um eine Zahl verschoben; ASource ist S bzw.
  /// P.</summary>
  function CountedString(ACount: TSyntaxNode; out ALength, ASource: TSyntaxNode): Boolean;
  var
    mSymbol, mType: TResolvedSymbol;
    mTypeName: string;
  begin
    Result := False;
    ALength := Unwrapped(ACount);
    if (ALength.Kind = TSyntaxKind.BinaryExpr) and MatchStr(ALength.Name, ['+', '-']) and
      (ALength.ChildCount = 2) then
    begin
      if Unwrapped(ALength[1]).Kind = TSyntaxKind.Literal then
      begin
        ALength := Unwrapped(ALength[0]);
      end
      else if Unwrapped(ALength[0]).Kind = TSyntaxKind.Literal then
      begin
        ALength := Unwrapped(ALength[1]);
      end;
    end;
    if not IsCallOf(ALength, 'Length') and not IsCallOf(ALength, 'StrLen') then
    begin
      Exit;
    end;
    ASource := Unwrapped(ALength[1]);
    if SameText(ALength.Name, 'Length') then
    begin
      Result := mScope.SureType(ASource, mSymbol, mType) and (mType.Builtin or SameText(mType.UnitName, 'System')) and
        TMigrationTypes.IsUnicodeString(mType.Name);
    end
    else
    begin
      Result := DeclaredTypeName(mScope, AContext, ASource, mTypeName) and
        TMigrationTypes.IsWideCharPointer(mTypeName);
    end;
  end;

  /// <summary>Stammt der Puffer ABuffer aus ASource: S, S[…], @S[…], PChar(S), Pointer(S)^ …?</summary>
  function BufferOf(ABuffer, ASource: TSyntaxNode): Boolean;
  var
    mNode: TSyntaxNode;
    mSource: string;
  begin
    mSource := mScope.Text(ASource);
    mNode := Unwrapped(ABuffer);
    while True do
    begin
      if mScope.Text(mNode) = mSource then
      begin
        Exit(True);
      end;
      if (mNode.Kind in [TSyntaxKind.AddressOf, TSyntaxKind.Dereference]) and (mNode.ChildCount > 0) then
      begin
        mNode := Unwrapped(mNode[0]);
      end
      else if (mNode.Kind = TSyntaxKind.IndexAccess) and (mNode.ChildCount > 1) then
      begin
        mNode := Unwrapped(mNode[0]);
      end
      else if (mNode.Kind = TSyntaxKind.Call) and (mNode.ChildCount = 2) and
        MatchText(mNode.Name, ['PChar', 'PWideChar', 'Pointer', 'PByte']) then
      begin
        mNode := Unwrapped(mNode[1]);
      end
      else
      begin
        Exit(False);
      end;
    end;
  end;

  /// <summary>Ist das erste Argument von GetMem/ReallocMem sicher ein PChar?</summary>
  function CharPointerTarget(ANode: TSyntaxNode; out ATypeName: string): Boolean;
  begin
    Result := DeclaredTypeName(mScope, AContext, Unwrapped(ANode[1]), ATypeName) and
      TMigrationTypes.IsWideCharPointer(ATypeName);
  end;

  procedure CheckCall(ANode: TSyntaxNode);
  var
    mBuffers: TArray<Integer>;
    mCount, mBuffer: Integer;
    mCountNode, mLength, mSource: TSyntaxNode;
    mFound: Boolean;
    mTypeName, mNewText, mMessage: string;
  begin
    if not (ANode[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
    begin
      Exit;
    end;
    mCount := CountArgument(ANode.Name, ANode[0].Kind = TSyntaxKind.MemberAccess, mBuffers);
    if (mCount < 0) or (ANode.ChildCount <= mCount + 1) or not mMigration.Reportable(ANode.StartPos) then
    begin
      Exit;
    end;
    mCountNode := ANode[mCount + 1];
    if not CountedString(mCountNode, mLength, mSource) then
    begin
      Exit;
    end;
    if mBuffers = nil then
    begin
      if not CharPointerTarget(ANode, mTypeName) then
      begin
        Exit;
      end;
      mMessage := cTexts[TMigrationUnicodeText.CountAllocates].Fmt([mScope.Text(mLength), ANode.Name,
        mScope.Text(ANode[1]), mTypeName]);
    end
    else
    begin
      mFound := False;
      for mBuffer in mBuffers do
      begin
        mFound := mFound or ((mBuffer + 1 < ANode.ChildCount) and BufferOf(ANode[mBuffer + 1], mSource));
      end;
      if not mFound then
      begin
        Exit;
      end;
      mMessage := cTexts[TMigrationUnicodeText.CountCopies].Fmt([mScope.Text(mLength), ANode.Name]);
    end;
    mNewText := mScope.Text(mCountNode);
    if Unwrapped(mCountNode).Kind = TSyntaxKind.BinaryExpr then
    begin
      mNewText := '(' + mNewText + ')';
    end;
    AReport.Add(NodeRange(mCountNode), mMessage, TRuleConfidence.High,
      [TRuleFix.Create(cTexts[TMigrationUnicodeText.MultiplySize].Text,
      [TTextEdit.Create(NodeRange(mCountNode), mNewText + ' * SizeOf(Char)')])]);
  end;

var
  mNode: TSyntaxNode;
begin
  if not Applicable(AContext) then
  begin
    Exit;
  end;
  mMigration := TMigrationScope.Create(AContext);
  mScope := TTypedScope.Create(AContext);
  try
    for mNode in CallsOf(AContext.Tree.Root) do
    begin
      CheckCall(mNode);
    end;
  finally
    mScope.Free;
    mMigration.Free;
  end;
end;

{ TAnsiApiCallRule }

function TAnsiApiCallRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cAnsiApiCallRuleId, TRuleSeverity.Warning,
    cTexts[TMigrationUnicodeText.ApiTitle].Text);
end;

class function TAnsiApiCallRule.NeutralName(const AName: string): string;
begin
  Result := '';
  // Kleinbuchstabe oder Ziffer vor dem A: MessageBoxA, lstrlenA, RegOpenKeyExA, nicht DATA oder LeseDATA.
  if (Length(AName) >= 3) and (AName[Length(AName)] = 'A') and
    CharInSet(AName[Length(AName) - 1], ['a'..'z', '0'..'9']) and CharInSet(AName[1], ['A'..'Z', 'a'..'z']) then
  begin
    Result := Copy(AName, 1, Length(AName) - 1);
  end;
end;

procedure TAnsiApiCallRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScope: TTypedScope;
  mMigration: TMigrationScope;

  /// <summary>PAnsiChar(AnsiString(S)) mit S sicher string; AString ist S.</summary>
  function ConvertedString(AArgument: TSyntaxNode; out AString: TSyntaxNode): Boolean;
  var
    mInner: TSyntaxNode;
    mSymbol, mType: TResolvedSymbol;
  begin
    Result := False;
    mInner := Unwrapped(AArgument);
    if not IsCallOf(mInner, 'PAnsiChar') then
    begin
      Exit;
    end;
    mInner := Unwrapped(mInner[1]);
    if not IsCallOf(mInner, 'AnsiString') then
    begin
      Exit;
    end;
    AString := Unwrapped(mInner[1]);
    Result := mScope.SureType(AString, mSymbol, mType) and (mType.Builtin or SameText(mType.UnitName, 'System')) and
      TMigrationTypes.IsUnicodeString(mType.Name);
  end;

  /// <summary>Ist AArgument sicher ein Ansi-Typ (PAnsiChar, AnsiString, AnsiChar …)?</summary>
  function SureAnsi(AArgument: TSyntaxNode): Boolean;
  var
    mTypeName: string;
  begin
    Result := DeclaredTypeName(mScope, AContext, Unwrapped(AArgument), mTypeName) and
      ContainsText(mTypeName, 'Ansi');
  end;

  function Converted(const AConverted: TArray<Integer>; AIndex: Integer): Boolean;
  var
    mEntry: Integer;
  begin
    Result := False;
    for mEntry in AConverted do
    begin
      Result := Result or (mEntry = AIndex);
    end;
  end;

  /// <summary>Darf die Korrektur auf die Funktion ohne A umstellen?</summary>
  function NeutralAllowed(ANode: TSyntaxNode; const AConverted: TArray<Integer>): Boolean;
  var
    mTarget: TResolvedSymbol;
    mIndex: Integer;
  begin
    mTarget := mScope.Resolver.Resolve(AContext.Tree, mScope.FileName, ANode[0].StartPos);
    Result := not mTarget.Found or StartsText('Winapi.', mTarget.UnitName);
    for mIndex := 1 to ANode.ChildCount - 1 do
    begin
      if Result and not Converted(AConverted, mIndex) and SureAnsi(ANode[mIndex]) then
      begin
        Result := False;
      end;
    end;
  end;

  procedure CheckCall(ANode: TSyntaxNode);
  var
    mNeutral, mFirst: string;
    mIndex: Integer;
    mString: TSyntaxNode;
    mConverted: TArray<Integer>;
    mEdits: TArray<TTextEdit>;
    mFixes: TArray<TRuleFix>;
  begin
    if ANode[0].Kind <> TSyntaxKind.Identifier then
    begin
      Exit;
    end;
    mNeutral := NeutralName(ANode.Name);
    if (mNeutral = '') or not mMigration.Reportable(ANode.StartPos) then
    begin
      Exit;
    end;
    mConverted := nil;
    mEdits := [TTextEdit.Create(NodeRange(ANode[0]), mNeutral)];
    for mIndex := 1 to ANode.ChildCount - 1 do
    begin
      if ConvertedString(ANode[mIndex], mString) then
      begin
        if mConverted = nil then
        begin
          mFirst := mScope.Text(mString);
        end;
        mConverted := mConverted + [mIndex];
        mEdits := mEdits + [TTextEdit.Create(NodeRange(ANode[mIndex]), 'PChar(' + mScope.Text(mString) + ')')];
      end;
    end;
    if mConverted = nil then
    begin
      Exit;
    end;
    mFixes := nil;
    if NeutralAllowed(ANode, mConverted) then
    begin
      mFixes := [TRuleFix.Create(cTexts[TMigrationUnicodeText.UseNeutral].Fmt([mNeutral]), mEdits)];
    end;
    AReport.Add(NodeRange(ANode[0]), cTexts[TMigrationUnicodeText.ApiLoses].Fmt([ANode.Name, mFirst, mNeutral]),
      TRuleConfidence.High, mFixes);
  end;

var
  mNode: TSyntaxNode;
begin
  if not Applicable(AContext) then
  begin
    Exit;
  end;
  mMigration := TMigrationScope.Create(AContext);
  mScope := TTypedScope.Create(AContext);
  try
    for mNode in CallsOf(AContext.Tree.Root) do
    begin
      CheckCall(mNode);
    end;
  finally
    mScope.Free;
    mMigration.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Migration.Unicode', cTexts);

end.
