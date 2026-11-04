unit Atlas.Common.Rules.Builtin.DllExports;

// Regeln für exportierte Routinen (#909, Gruppe Robustheit und Muster):
//   dll-export-unsafe  In exports aufgeführte Routine dieser Datei (#973) ohne
//                      Aufrufkonvention (stdcall, cdecl, safecall, winapi,
//                      pascal) oder mit string, dynamischem Array, Objekt oder
//                      Interface ohne GUID als Parameter bzw. Ergebnis. Strings
//                      und dynamische Arrays bleiben still, wenn ShareMem (bzw.
//                      SimpleShareMem) eingebunden ist und allowShareMem an ist.
//                      Objekte erkennt die Regel nur sicher: Klassen der Datei,
//                      des Index und häufige RTL-Klassen; Interfaces nur aus der
//                      Datei. Korrektur: stdcall in jedem Kopf der Routine.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  DllExportUnsafeRuleId = 'dll-export-unsafe';

type
  TDllExportUnsafeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterDllExportRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Options;

const
  CallingConventions: array[0..4] of string = ('stdcall', 'cdecl', 'safecall', 'winapi', 'pascal');
  /// <summary>Strings mit Referenzzählung im Speicher des Delphi-Speichermanagers; WideString (BSTR) und
  /// ShortString sind sicher.</summary>
  ManagedStrings: array[0..4] of string = ('string', 'UnicodeString', 'AnsiString', 'UTF8String', 'RawByteString');
  /// <summary>Dynamische Arrays aus System und System.Types.</summary>
  DynamicArrays: array[0..1] of string = ('TBytes', 'TArray');
  /// <summary>Häufige RTL-Klassen; ohne Index wären sie unbekannt.</summary>
  KnownClasses: array[0..19] of string = ('TObject', 'TPersistent', 'TComponent', 'TStrings', 'TStringList',
    'TStream', 'TMemoryStream', 'TFileStream', 'TStringStream', 'TBytesStream', 'TList', 'TObjectList',
    'TDictionary', 'TObjectDictionary', 'TQueue', 'TStack', 'TCollection', 'TThread', 'TJSONObject', 'TJSONArray');
  ShareMemUnits: array[0..1] of string = ('ShareMem', 'SimpleShareMem');

type
  {$SCOPEDENUMS ON}
  TExportTypeKind = (Safe, ManagedString, DynamicArray, ObjectType, InterfaceWithoutGuid);
  {$SCOPEDENUMS OFF}

  /// <summary>Eintrag in exports: Name, Token des Namens und die Parameterliste bei Überladungen.</summary>
  TExportEntry = record
    Name: string;
    Token: TPascalToken;
    /// <summary>"(const A: string; var B: Integer)" normalisiert, '' ohne Liste.</summary>
    Parameters: string;
  end;

function NodeText(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

/// <summary>Kleinbuchstaben ohne Leerraum: Parameterlisten vergleichen.</summary>
function Normalized(const AText: string): string;
var
  Ch: Char;
begin
  Result := '';
  for Ch in LowerCase(AText) do
  begin
    if not CharInSet(Ch, [' ', #9, #10, #13]) then
    begin
      Result := Result + Ch;
    end;
  end;
end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

/// <summary>Index der schließenden Klammer zur öffnenden an AIndex (oder das letzte Token).</summary>
function ClosingParen(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
var
  mDepth: Integer;
begin
  Result := AIndex;
  mDepth := 0;
  repeat
    if ATokens[Result].IsSymbol('(') then
    begin
      Inc(mDepth);
    end
    else if ATokens[Result].IsSymbol(')') then
    begin
      Dec(mDepth);
    end;
    if mDepth <> 0 then
    begin
      Inc(Result);
    end;
  until (mDepth = 0) or (Result >= High(ATokens));
end;

/// <summary>Eintrag ab dem Bezeichner an AIndex; AIndex steht danach auf seinem letzten Token.</summary>
function ReadEntry(const AContext: TRuleContext; const ATokens: TArray<TPascalToken>;
  var AIndex: Integer): TExportEntry;
var
  mListStart: Integer;
begin
  Result := Default(TExportEntry);
  Result.Name := ATokens[AIndex].Text;
  Result.Token := ATokens[AIndex];
  // Unit.Routine: der letzte Teil zählt.
  while (AIndex + 2 <= High(ATokens)) and ATokens[AIndex + 1].IsSymbol('.') and
    (ATokens[AIndex + 2].Kind = TPascalTokenKind.Identifier) do
  begin
    Inc(AIndex, 2);
    Result.Name := ATokens[AIndex].Text;
    Result.Token := ATokens[AIndex];
  end;
  if (AIndex + 1 <= High(ATokens)) and ATokens[AIndex + 1].IsSymbol('(') then
  begin
    mListStart := AIndex + 1;
    AIndex := ClosingParen(ATokens, mListStart);
    Result.Parameters := Normalized(Copy(AContext.Text, ATokens[mListStart].Offset + 1,
      ATokens[AIndex].Offset + Length(ATokens[AIndex].Text) - ATokens[mListStart].Offset));
  end;
end;

/// <summary>Einträge des exports-Abschnitts ab AIndex bis zum ";" an AEntries anhängen; AIndex steht danach auf
/// dem ";".</summary>
procedure ReadExports(const AContext: TRuleContext; const ATokens: TArray<TPascalToken>; var AIndex: Integer;
  var AEntries: TArray<TExportEntry>);
var
  mExpect: Boolean;
begin
  mExpect := True;
  while (AIndex <= High(ATokens)) and not ATokens[AIndex].IsSymbol(';') do
  begin
    if IsTrivia(ATokens[AIndex]) then
    begin
      // Kommentare und Direktiven zwischen den Einträgen überspringen.
    end
    else if ATokens[AIndex].IsSymbol(',') then
    begin
      mExpect := True;
    end
    else if mExpect and (ATokens[AIndex].Kind = TPascalTokenKind.Identifier) then
    begin
      mExpect := False;
      AEntries := AEntries + [ReadEntry(AContext, ATokens, AIndex)];
    end;
    Inc(AIndex);
  end;
end;

/// <summary>Einträge aller exports-Abschnitte aus den Token.</summary>
function ExportEntries(const AContext: TRuleContext): TArray<TExportEntry>;
var
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
begin
  Result := nil;
  mTokens := AContext.Tree.Tokens;
  mIndex := 0;
  while mIndex <= High(mTokens) do
  begin
    if mTokens[mIndex].IsKeyword('exports') then
    begin
      Inc(mIndex);
      ReadExports(AContext, mTokens, mIndex, Result);
    end
    else
    begin
      Inc(mIndex);
    end;
  end;
end;

/// <summary>Köpfe der Routine AName in dieser Datei: Deklarationen im interface und Rümpfe; Methoden nicht.
/// </summary>
function RoutineHeaders(ATree: TSyntaxTree; const AName: string): TArray<TSyntaxNode>;
var
  Found: TArray<TSyntaxNode>;
begin
  Found := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Header: TSyntaxNode;
    begin
      // Nicht in Typen (Methoden) und nicht in Rümpfe (verschachtelte Routinen).
      Result := not (ANode.Kind in [TSyntaxKind.TypeSection, TSyntaxKind.Block, TSyntaxKind.RoutineDecl]);
      Header := nil;
      if ANode.Kind = TSyntaxKind.RoutineDecl then
      begin
        Header := ANode.FindChild(TSyntaxKind.RoutineHeader);
      end
      else if (ANode.Kind = TSyntaxKind.RoutineHeader) and (ANode.Parent <> nil) and
        (ANode.Parent.Kind = TSyntaxKind.InterfaceSection) then
      begin
        Header := ANode;
      end;
      if (Header <> nil) and SameText(Header.Name, AName) then
      begin
        Found := Found + [Header];
      end;
    end);
  Result := Found;
end;

function ParameterText(const AText: string; AHeader: TSyntaxNode): string;
var
  Parameters: TSyntaxNode;
begin
  Result := '';
  Parameters := AHeader.FindChild(TSyntaxKind.Parameters);
  if Parameters <> nil then
  begin
    Result := Normalized(NodeText(AText, Parameters));
  end;
end;

/// <summary>Typdeklaration ATypeName in der Datei; nil ohne.</summary>
function FileTypeDecl(ATree: TSyntaxTree; const ATypeName: string): TSyntaxNode;
var
  Found: TSyntaxNode;
begin
  Found := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := Found = nil;
      if Result and (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, ATypeName) then
      begin
        Found := ANode;
      end;
    end);
  Result := Found;
end;

/// <summary>Hat die Interface-Deklaration AInterface eine GUID ['{…}'] oder ist sie ein dispinterface?</summary>
function HasGuid(const AText: string; AInterface: TSyntaxNode): Boolean;
begin
  Result := StartsText('dispinterface', TrimLeft(NodeText(AText, AInterface))) or
    ((AInterface.ChildCount > 0) and (AInterface[0].Kind = TSyntaxKind.Literal) and
    (Pos('{', AInterface[0].Name) > 0));
end;

function KindOf(const AContext: TRuleContext; const ATypeName: string; ADepth: Integer): TExportTypeKind; forward;

/// <summary>Name ohne Typparameter und Unit ("System.SysUtils.TBytes" wird "TBytes").</summary>
function BareTypeName(const ATypeName: string): string;
begin
  Result := Trim(ATypeName);
  if Pos('<', Result) > 0 then
  begin
    Result := Trim(Copy(Result, 1, Pos('<', Result) - 1));
  end;
  if LastDelimiter('.', Result) > 0 then
  begin
    Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
  end;
end;

/// <summary>Art des Typs ATypeName ohne Deklaration: Strings und dynamische Arrays aus System.</summary>
function SystemKind(const AName: string): TExportTypeKind;
begin
  Result := TExportTypeKind.Safe;
  if MatchText(AName, ManagedStrings) then
  begin
    Result := TExportTypeKind.ManagedString;
  end
  else if MatchText(AName, DynamicArrays) or EndsText('DynArray', AName) then
  begin
    Result := TExportTypeKind.DynamicArray;
  end;
end;

/// <summary>Bestimmt das Kind AChild einer Typdeklaration AName die Art (AKind)?</summary>
function ChildKind(const AContext: TRuleContext; AChild: TSyntaxNode; const AName: string; ADepth: Integer;
  out AKind: TExportTypeKind): Boolean;
begin
  AKind := TExportTypeKind.Safe;
  case AChild.Kind of
    TSyntaxKind.ClassType:
      AKind := TExportTypeKind.ObjectType;
    TSyntaxKind.ArrayType:
      // array of X ist dynamisch, array[0..3] of X nicht.
      if Pos('[', NodeText(AContext.Text, AChild)) = 0 then
      begin
        AKind := TExportTypeKind.DynamicArray;
      end;
    TSyntaxKind.InterfaceType:
      if not HasGuid(AContext.Text, AChild) then
      begin
        AKind := TExportTypeKind.InterfaceWithoutGuid;
      end;
    TSyntaxKind.TypeReference:
      // Alias: TNamen = string
      if (ADepth < 8) and not SameText(AChild.Name, AName) then
      begin
        AKind := KindOf(AContext, NodeText(AContext.Text, AChild), ADepth + 1);
        Exit(True);
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
  Result := AKind <> TExportTypeKind.Safe;
end;

/// <summary>Art des in der Datei deklarierten Typs ADecl (Name AName).</summary>
function DeclKind(const AContext: TRuleContext; ADecl: TSyntaxNode; const AName: string;
  ADepth: Integer): TExportTypeKind;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ADecl.ChildCount - 1 do
  begin
    if ChildKind(AContext, ADecl[mIndex], AName, ADepth, Result) then
    begin
      Exit;
    end;
  end;
  Result := TExportTypeKind.Safe;
end;

/// <summary>Ist AName eine Klasse aus der RTL oder dem Index?</summary>
function IsExternalClass(const AContext: TRuleContext; const AName: string): Boolean;
var
  mLocation: TSymbolLocation;
begin
  Result := MatchText(AName, KnownClasses);
  if Result or (AContext.Index = nil) then
  begin
    Exit;
  end;
  for mLocation in AContext.Index.FindSymbols(AName) do
  begin
    if (mLocation.Symbol.Container = '') and (mLocation.Symbol.Kind = TIndexSymbolKind.ClassType) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Art des Typs ATypeName an der Grenze einer DLL; Safe, wenn er sicher ist oder sich nicht sicher
/// bestimmen lässt. ADepth begrenzt Alias-Ketten.</summary>
function KindOf(const AContext: TRuleContext; const ATypeName: string; ADepth: Integer): TExportTypeKind;
var
  mName: string;
  mDecl: TSyntaxNode;
begin
  mName := BareTypeName(ATypeName);
  Result := SystemKind(mName);
  if Result <> TExportTypeKind.Safe then
  begin
    Exit;
  end;
  mDecl := FileTypeDecl(AContext.Tree, mName);
  if mDecl <> nil then
  begin
    Result := DeclKind(AContext, mDecl, mName, ADepth);
  end
  else if IsExternalClass(AContext, mName) then
  begin
    Result := TExportTypeKind.ObjectType;
  end;
end;

function UsesShareMem(ATree: TSyntaxTree): Boolean;
var
  Found: Boolean;
begin
  Found := False;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Name: string;
    begin
      Result := not Found;
      if ANode.Kind <> TSyntaxKind.UsedUnit then
      begin
        Exit;
      end;
      Name := ANode.Name;
      if LastDelimiter('.', Name) > 0 then
      begin
        Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
      end;
      if MatchText(Name, ShareMemUnits) then
      begin
        Found := True;
      end;
    end);
  Result := Found;
end;

/// <summary>"string", "TStringList (Objekt)" usw. für die Meldung.</summary>
function Described(const ATypeName: string; AKind: TExportTypeKind): string;
begin
  Result := Trim(ATypeName);
  case AKind of
    TExportTypeKind.DynamicArray:
      Result := Result + ' (dynamisches Array)';
    TExportTypeKind.ObjectType:
      Result := Result + ' (Objekt)';
    TExportTypeKind.InterfaceWithoutGuid:
      Result := Result + ' (Interface ohne GUID)';
    TExportTypeKind.Safe: ;
    TExportTypeKind.ManagedString: ;
  end;
end;

function Joined(const AParts: TArray<string>): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(AParts) do
  begin
    if Index = 0 then
    begin
      Result := AParts[Index];
    end
    else if Index = High(AParts) then
    begin
      Result := Result + ' und ' + AParts[Index];
    end
    else
    begin
      Result := Result + ', ' + AParts[Index];
    end;
  end;
end;

{ TDllExportUnsafeRule }

function TDllExportUnsafeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(DllExportUnsafeRuleId, TRuleSeverity.Warning,
    'Exportierte Routine nicht sicher über DLL-Grenzen aufrufbar');
end;

/// <summary>Köpfe der Gruppe zum Eintrag AEntry: Überladungen wählt die Parameterliste im exports-Eintrag;
/// Köpfe ohne Liste (Rumpf zu einer Deklaration im interface) gehören zu jeder. AMain: der erste Kopf mit
/// Liste, sonst der erste.</summary>
function GroupOf(const AText: string; const AEntry: TExportEntry; const AHeaders: TArray<TSyntaxNode>;
  out AMain: TSyntaxNode): TArray<TSyntaxNode>;
var
  mHeader: TSyntaxNode;
  mText: string;
begin
  Result := nil;
  AMain := nil;
  for mHeader in AHeaders do
  begin
    mText := ParameterText(AText, mHeader);
    if (AEntry.Parameters = '') or (mText = '') or (mText = AEntry.Parameters) then
    begin
      Result := Result + [mHeader];
      if (AMain = nil) and (mText <> '') then
      begin
        AMain := mHeader;
      end;
    end;
  end;
  if (AMain = nil) and (Result <> nil) then
  begin
    AMain := Result[0];
  end;
end;

/// <summary>Haben alle Köpfe der Gruppe mit Liste dieselbe wie AMain? Ohne Liste im Eintrag muss die Routine
/// eindeutig sein.</summary>
function Unambiguous(const AText: string; const AGroup: TArray<TSyntaxNode>; AMain: TSyntaxNode): Boolean;
var
  mHeader: TSyntaxNode;
  mText, mOther: string;
begin
  mText := ParameterText(AText, AMain);
  for mHeader in AGroup do
  begin
    mOther := ParameterText(AText, mHeader);
    if (mOther <> '') and (mOther <> mText) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

/// <summary>Nennt ein Kopf der Gruppe eine Aufrufkonvention?</summary>
function HasConvention(const AGroup: TArray<TSyntaxNode>): Boolean;
var
  mHeader: TSyntaxNode;
  mIndex: Integer;
begin
  for mHeader in AGroup do
  begin
    for mIndex := 0 to mHeader.ChildCount - 1 do
    begin
      if (mHeader[mIndex].Kind = TSyntaxKind.Directive) and MatchText(mHeader[mIndex].Name, CallingConventions) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

type
  /// <summary>Probleme einer exportierten Routine für die Meldung.</summary>
  TExportProblems = record
    Parts: TArray<string>;
    /// <summary>Strings oder dynamische Arrays: Speicher des Delphi-Speichermanagers.</summary>
    Memory: Boolean;
    IsFunction: Boolean;
  end;

/// <summary>Art des Typverweises ATypeRef; Strings und dynamische Arrays sind mit AAllowStrings sicher.</summary>
function BoundaryKind(const AContext: TRuleContext; ATypeRef: TSyntaxNode; AAllowStrings: Boolean): TExportTypeKind;
begin
  Result := KindOf(AContext, NodeText(AContext.Text, ATypeRef), 0);
  if AAllowStrings and (Result in [TExportTypeKind.ManagedString, TExportTypeKind.DynamicArray]) then
  begin
    Result := TExportTypeKind.Safe;
  end;
end;

/// <summary>Ergebnis: der Typverweis direkt im Kopf AMain.</summary>
procedure CollectResult(const AContext: TRuleContext; AMain: TSyntaxNode; AAllowStrings: Boolean;
  var AProblems: TExportProblems);
var
  mTypeRef: TSyntaxNode;
  mKind: TExportTypeKind;
begin
  mTypeRef := AMain.FindChild(TSyntaxKind.TypeReference);
  if mTypeRef = nil then
  begin
    Exit;
  end;
  AProblems.IsFunction := True;
  mKind := BoundaryKind(AContext, mTypeRef, AAllowStrings);
  if mKind <> TExportTypeKind.Safe then
  begin
    AProblems.Parts := AProblems.Parts + [Format('gibt %s zurück', [Described(NodeText(AContext.Text, mTypeRef),
      mKind)])];
  end;
  AProblems.Memory := mKind in [TExportTypeKind.ManagedString, TExportTypeKind.DynamicArray];
end;

procedure CollectParameter(const AContext: TRuleContext; AParameter: TSyntaxNode; AAllowStrings: Boolean;
  var AProblems: TExportProblems);
var
  mTypeRef: TSyntaxNode;
  mKind: TExportTypeKind;
  mName: string;
begin
  mTypeRef := AParameter.FindChild(TSyntaxKind.TypeReference);
  if (AParameter.Kind <> TSyntaxKind.Parameter) or (mTypeRef = nil) then
  begin
    Exit;
  end;
  mKind := BoundaryKind(AContext, mTypeRef, AAllowStrings);
  if mKind = TExportTypeKind.Safe then
  begin
    Exit;
  end;
  for mName in AParameter.Name.Split([',']) do
  begin
    AProblems.Parts := AProblems.Parts + [Format('hat den Parameter %s: %s', [Trim(mName),
      Described(NodeText(AContext.Text, mTypeRef), mKind)])];
  end;
  AProblems.Memory := AProblems.Memory or (mKind in [TExportTypeKind.ManagedString, TExportTypeKind.DynamicArray]);
end;

function ProblemsOf(const AContext: TRuleContext; AMain: TSyntaxNode; AAllowStrings,
  AConvention: Boolean): TExportProblems;
var
  mParameters: TSyntaxNode;
  mIndex: Integer;
begin
  Result := Default(TExportProblems);
  CollectResult(AContext, AMain, AAllowStrings, Result);
  mParameters := AMain.FindChild(TSyntaxKind.Parameters);
  if mParameters <> nil then
  begin
    for mIndex := 0 to mParameters.ChildCount - 1 do
    begin
      CollectParameter(AContext, mParameters[mIndex], AAllowStrings, Result);
    end;
  end;
  if not AConvention then
  begin
    Result.Parts := Result.Parts + ['hat keine Aufrufkonvention'];
  end;
end;

function MessageOf(const AProblems: TExportProblems): string;
begin
  Result := 'Exportierte Prozedur ';
  if AProblems.IsFunction then
  begin
    Result := 'Exportierte Funktion ';
  end;
  Result := Result + Joined(AProblems.Parts);
  if AProblems.Memory then
  begin
    Result := Result + '; Aufrufer ohne ShareMem stürzen ab. Besser PChar mit Puffer und Länge übergeben.';
  end
  else
  begin
    Result := Result + '; Aufrufer aus anderen Sprachen oder Delphi-Versionen stürzen ab.';
  end;
end;

/// <summary>Korrektur: stdcall in jedem Kopf der Gruppe.</summary>
function StdcallFix(const AGroup: TArray<TSyntaxNode>): TArray<TRuleFix>;
var
  mHeader: TSyntaxNode;
  mEdits: TArray<TRuleEdit>;
begin
  mEdits := nil;
  for mHeader in AGroup do
  begin
    mEdits := mEdits + [TRuleEdit.Create(TTextRange.Create(mHeader.EndPos, mHeader.EndPos), ' stdcall;')];
  end;
  // Ändert die Schnittstelle für vorhandene Aufrufer: nur einzeln.
  Result := [TRuleFix.Create('Aufrufkonvention stdcall ergänzen', mEdits, False)];
end;

procedure TDllExportUnsafeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mEntry: TExportEntry;
  mGroup: TArray<TSyntaxNode>;
  mMain: TSyntaxNode;
  mAllowStrings, mConvention: Boolean;
  mProblems: TExportProblems;
  mFixes: TArray<TRuleFix>;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mAllowStrings := TRuleOptions.Bool(AContext.Options, 'allowShareMem', True) and UsesShareMem(AContext.Tree);
  for mEntry in ExportEntries(AContext) do
  begin
    mGroup := GroupOf(AContext.Text, mEntry, RoutineHeaders(AContext.Tree, mEntry.Name), mMain);
    // Routine aus einer anderen Unit: hier nicht zu beurteilen.
    if (mGroup = nil) or not Unambiguous(AContext.Text, mGroup, mMain) then
    begin
      Continue;
    end;
    mConvention := HasConvention(mGroup);
    mProblems := ProblemsOf(AContext, mMain, mAllowStrings, mConvention);
    if mProblems.Parts = nil then
    begin
      Continue;
    end;
    mFixes := nil;
    if not mConvention then
    begin
      mFixes := StdcallFix(mGroup);
    end;
    AReport.Add(TTextRange.Create(mEntry.Token.StartPos, mEntry.Token.EndPos), MessageOf(mProblems),
      TRuleConfidence.High, mFixes);
  end;
end;

procedure RegisterDllExportRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TDllExportUnsafeRule.Create);
end;

end.
