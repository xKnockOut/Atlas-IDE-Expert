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

/// <summary>Einträge aller exports-Abschnitte aus den Token.</summary>
function ExportEntries(const AContext: TRuleContext): TArray<TExportEntry>;
var
  Tokens: TArray<TPascalToken>;
  Index, Depth, ListStart: Integer;
  Entry: TExportEntry;
  Expect: Boolean;
begin
  Result := nil;
  Tokens := AContext.Tree.Tokens;
  Index := 0;
  while Index <= High(Tokens) do
  begin
    if not Tokens[Index].IsKeyword('exports') then
    begin
      Inc(Index);
      Continue;
    end;
    Inc(Index);
    Expect := True;
    while (Index <= High(Tokens)) and not Tokens[Index].IsSymbol(';') do
    begin
      if IsTrivia(Tokens[Index]) then
      begin
        Inc(Index);
        Continue;
      end;
      if Tokens[Index].IsSymbol(',') then
      begin
        Expect := True;
      end
      else if Expect and (Tokens[Index].Kind = TPascalTokenKind.Identifier) then
      begin
        Expect := False;
        Entry := Default(TExportEntry);
        Entry.Name := Tokens[Index].Text;
        Entry.Token := Tokens[Index];
        // Unit.Routine: der letzte Teil zählt.
        while (Index + 2 <= High(Tokens)) and Tokens[Index + 1].IsSymbol('.') and
          (Tokens[Index + 2].Kind = TPascalTokenKind.Identifier) do
        begin
          Inc(Index, 2);
          Entry.Name := Tokens[Index].Text;
          Entry.Token := Tokens[Index];
        end;
        if (Index + 1 <= High(Tokens)) and Tokens[Index + 1].IsSymbol('(') then
        begin
          ListStart := Index + 1;
          Depth := 0;
          repeat
            Inc(Index);
            if Tokens[Index].IsSymbol('(') then
            begin
              Inc(Depth);
            end
            else if Tokens[Index].IsSymbol(')') then
            begin
              Dec(Depth);
            end;
          until (Depth = 0) or (Index = High(Tokens));
          Entry.Parameters := Normalized(Copy(AContext.Text, Tokens[ListStart].Offset + 1,
            Tokens[Index].Offset + Length(Tokens[Index].Text) - Tokens[ListStart].Offset));
        end;
        Result := Result + [Entry];
      end;
      Inc(Index);
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

/// <summary>Art des Typs ATypeName an der Grenze einer DLL; Safe, wenn er sicher ist oder sich nicht sicher
/// bestimmen lässt. ADepth begrenzt Alias-Ketten.</summary>
function KindOf(const AContext: TRuleContext; const ATypeName: string; ADepth: Integer): TExportTypeKind;
var
  Name: string;
  Decl, Child: TSyntaxNode;
  Location: TSymbolLocation;
  Index: Integer;
begin
  Result := TExportTypeKind.Safe;
  Name := Trim(ATypeName);
  if Pos('<', Name) > 0 then
  begin
    Name := Trim(Copy(Name, 1, Pos('<', Name) - 1));
  end;
  // System.string, System.SysUtils.TBytes
  if LastDelimiter('.', Name) > 0 then
  begin
    Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  end;
  if MatchText(Name, ManagedStrings) then
  begin
    Exit(TExportTypeKind.ManagedString);
  end;
  if MatchText(Name, DynamicArrays) or EndsText('DynArray', Name) then
  begin
    Exit(TExportTypeKind.DynamicArray);
  end;
  Decl := FileTypeDecl(AContext.Tree, Name);
  if Decl <> nil then
  begin
    for Index := 0 to Decl.ChildCount - 1 do
    begin
      Child := Decl[Index];
      case Child.Kind of
        TSyntaxKind.ClassType:
          Exit(TExportTypeKind.ObjectType);
        TSyntaxKind.ArrayType:
          // array of X ist dynamisch, array[0..3] of X nicht.
          if Pos('[', NodeText(AContext.Text, Child)) = 0 then
          begin
            Exit(TExportTypeKind.DynamicArray);
          end;
        TSyntaxKind.InterfaceType:
          if not HasGuid(AContext.Text, Child) then
          begin
            Exit(TExportTypeKind.InterfaceWithoutGuid);
          end;
        TSyntaxKind.TypeReference:
          // Alias: TNamen = string
          if (ADepth < 8) and not SameText(Child.Name, Name) then
          begin
            Exit(KindOf(AContext, NodeText(AContext.Text, Child), ADepth + 1));
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
    end;
    Exit;
  end;
  if MatchText(Name, KnownClasses) then
  begin
    Exit(TExportTypeKind.ObjectType);
  end;
  if AContext.Index <> nil then
  begin
    for Location in AContext.Index.FindSymbols(Name) do
    begin
      if (Location.Symbol.Container = '') and (Location.Symbol.Kind = TIndexSymbolKind.ClassType) then
      begin
        Exit(TExportTypeKind.ObjectType);
      end;
    end;
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

procedure TDllExportUnsafeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Entry: TExportEntry;
  Headers, Group: TArray<TSyntaxNode>;
  Header, Main, Child, Parameters, TypeRef: TSyntaxNode;
  Index: Integer;
  Text, Name, Message: string;
  Convention, Memory, AllowStrings, IsFunction: Boolean;
  Kind: TExportTypeKind;
  Parts: TArray<string>;
  Edits: TArray<TRuleEdit>;
  Fixes: TArray<TRuleFix>;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  AllowStrings := TRuleOptions.Bool(AContext.Options, 'allowShareMem', True) and UsesShareMem(AContext.Tree);
  for Entry in ExportEntries(AContext) do
  begin
    Headers := RoutineHeaders(AContext.Tree, Entry.Name);
    // Überladungen: die Parameterliste im exports-Eintrag wählt; Köpfe ohne Liste (Rumpf zu einer Deklaration
    // im interface) gehören zu jeder.
    Group := nil;
    Main := nil;
    for Header in Headers do
    begin
      Text := ParameterText(AContext.Text, Header);
      if (Entry.Parameters = '') or (Text = '') or (Text = Entry.Parameters) then
      begin
        Group := Group + [Header];
        if (Main = nil) and (Text <> '') then
        begin
          Main := Header;
        end;
      end;
    end;
    // Routine aus einer anderen Unit: hier nicht zu beurteilen.
    if Group = nil then
    begin
      Continue;
    end;
    if Main = nil then
    begin
      Main := Group[0];
    end;
    // Ohne Liste im Eintrag muss die Routine eindeutig sein.
    Text := ParameterText(AContext.Text, Main);
    for Header in Group do
    begin
      if (ParameterText(AContext.Text, Header) <> '') and (ParameterText(AContext.Text, Header) <> Text) then
      begin
        Main := nil;
      end;
    end;
    if Main = nil then
    begin
      Continue;
    end;
    Convention := False;
    for Header in Group do
    begin
      for Index := 0 to Header.ChildCount - 1 do
      begin
        if (Header[Index].Kind = TSyntaxKind.Directive) and MatchText(Header[Index].Name, CallingConventions) then
        begin
          Convention := True;
        end;
      end;
    end;
    Parts := nil;
    Memory := False;
    IsFunction := False;
    // Ergebnis: der Typverweis direkt im Kopf
    TypeRef := Main.FindChild(TSyntaxKind.TypeReference);
    if TypeRef <> nil then
    begin
      IsFunction := True;
      Kind := KindOf(AContext, NodeText(AContext.Text, TypeRef), 0);
      if (Kind in [TExportTypeKind.ManagedString, TExportTypeKind.DynamicArray]) and AllowStrings then
      begin
        Kind := TExportTypeKind.Safe;
      end;
      if Kind <> TExportTypeKind.Safe then
      begin
        Parts := Parts + [Format('gibt %s zurück', [Described(NodeText(AContext.Text, TypeRef), Kind)])];
      end;
      Memory := Kind in [TExportTypeKind.ManagedString, TExportTypeKind.DynamicArray];
    end;
    Parameters := Main.FindChild(TSyntaxKind.Parameters);
    if Parameters <> nil then
    begin
      for Index := 0 to Parameters.ChildCount - 1 do
      begin
        Child := Parameters[Index];
        TypeRef := Child.FindChild(TSyntaxKind.TypeReference);
        if (Child.Kind <> TSyntaxKind.Parameter) or (TypeRef = nil) then
        begin
          Continue;
        end;
        Kind := KindOf(AContext, NodeText(AContext.Text, TypeRef), 0);
        if (Kind in [TExportTypeKind.ManagedString, TExportTypeKind.DynamicArray]) and AllowStrings then
        begin
          Kind := TExportTypeKind.Safe;
        end;
        if Kind = TExportTypeKind.Safe then
        begin
          Continue;
        end;
        for Name in Child.Name.Split([',']) do
        begin
          Parts := Parts + [Format('hat den Parameter %s: %s', [Trim(Name),
            Described(NodeText(AContext.Text, TypeRef), Kind)])];
        end;
        Memory := Memory or (Kind in [TExportTypeKind.ManagedString, TExportTypeKind.DynamicArray]);
      end;
    end;
    if not Convention then
    begin
      Parts := Parts + ['hat keine Aufrufkonvention'];
    end;
    if Parts = nil then
    begin
      Continue;
    end;
    Message := 'Exportierte Prozedur ';
    if IsFunction then
    begin
      Message := 'Exportierte Funktion ';
    end;
    Message := Message + Joined(Parts);
    if Memory then
    begin
      Message := Message + '; Aufrufer ohne ShareMem stürzen ab. Besser PChar mit Puffer und Länge übergeben.';
    end
    else
    begin
      Message := Message + '; Aufrufer aus anderen Sprachen oder Delphi-Versionen stürzen ab.';
    end;
    Fixes := nil;
    if not Convention then
    begin
      Edits := nil;
      for Header in Group do
      begin
        Edits := Edits + [TRuleEdit.Create(TTextRange.Create(Header.EndPos, Header.EndPos), ' stdcall;')];
      end;
      // Ändert die Schnittstelle für vorhandene Aufrufer: nur einzeln.
      Fixes := [TRuleFix.Create('Aufrufkonvention stdcall ergänzen', Edits, False)];
    end;
    AReport.Add(TTextRange.Create(Entry.Token.StartPos, Entry.Token.EndPos), Message, TRuleConfidence.High, Fixes);
  end;
end;

procedure RegisterDllExportRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TDllExportUnsafeRule.Create);
end;

end.
