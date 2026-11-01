unit Atlas.Common.Lsp.PublishedMembers;

// published-Properties und Ereignisse einer Komponentenklasse für den Hover,
// inklusive geerbter, mit Typ, default-Wert und deklarierender Klasse (#110).
//
// Die Klassen werden über den Symbolindex gefunden und ihre Deklaration aus
// dem Quelltext gelesen, weil der Index keine Sichtbarkeiten speichert.
// Mitglieder vor dem ersten Sichtbarkeitsabschnitt gelten als published
// (Komponenten werden mit {$M+} übersetzt). Eine Neudeklaration ohne Typ
// (property Caption;) macht eine geerbte Property published; Typ, default
// und deklarierende Klasse kommen dann vom Vorfahren.
//
// Ereignisse erkennt Atlas am Typ, nicht am Namen: ein Methodenzeiger
// (procedure/function … of object) oder eine Methodenreferenz
// (reference to …), auch über Aliase. Steht der Typ nicht im Index, gilt nur
// TNotifyEvent als Ereignis.
//
// Vorgabewerte: ausdrückliches default, implizites (Boolean False,
// Ganzzahlen 0, Aufzählungen ihr erster Wert), nodefault und stored
// erscheinen unterschiedlich; default an einer Array-Property heißt
// Standard-Property und steht als eigene Zeile.
//
// Für den Atlas-Tooltip liefert ToJson dieselben Mitglieder strukturiert
// (atlas.published): je Mitglied Name, Typ, Vorgabe samt Art, stored,
// deklarierende Klasse und Ereignis-Kennung, dazu die Standard-Property.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Index.Contract;

type
  TMemberReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  {$SCOPEDENUMS ON}
  TPublishedDefaultKind = (
    /// <summary>Keine Angabe, kein impliziter Wert bekannt.</summary>
    None,
    /// <summary>default Wert in der Deklaration.</summary>
    Explicit,
    /// <summary>Kein default, aber der Anfangswert des Typs (False, 0, erster Aufzählungswert).</summary>
    Implicit,
    /// <summary>nodefault: immer gespeichert.</summary>
    NoDefault);
  {$SCOPEDENUMS OFF}

  TPublishedMember = record
    Name: string;
    TypeName: string;
    /// <summary>Wert nach default bzw. der implizite Wert; '' ohne.</summary>
    DefaultValue: string;
    DefaultKind: TPublishedDefaultKind;
    /// <summary>Text nach stored (False, IsCaptionStored …); '' ohne Angabe.</summary>
    Stored: string;
    /// <summary>Klasse, die die Property mit Typ deklariert.</summary>
    DeclaringClass: string;
    /// <summary>Klasse, in der die Property published wird (Neudeklaration).</summary>
    PublishedIn: string;
    IsEvent: Boolean;
  end;

  TPublishedMembers = class
  public const
    /// <summary>Ab so vielen Einträgen werden nur noch Namen je Klasse gezeigt.</summary>
    CompactLimit = 40;
    MaxDepth = 32;
    /// <summary>Signatur, wenn der Ereignistyp nicht im Index steht.</summary>
    NotifyTail = '(Sender: TObject)';
    /// <summary>Alle published-Mitglieder, abgeleitete Klassen zuerst.</summary>
    class function Collect(const AIndex: ISymbolIndex; const AClassName: string;
      const AReadText: TMemberReadText): TArray<TPublishedMember>; static;
    /// <summary>Standard-Property der Klasse oder eines Vorfahren (Array-Property mit default), z. B.
    /// "Strings[Index: Integer]: string"; '' ohne.</summary>
    class function DefaultProperty(const AIndex: ISymbolIndex; const AClassName: string;
      const AReadText: TMemberReadText): string; static;
    /// <summary>Ist ATypeName ein Methodenzeiger oder eine Methodenreferenz (auch über Aliase)?</summary>
    class function IsEventType(const AIndex: ISymbolIndex; const AReadText: TMemberReadText;
      const ATypeName: string): Boolean; static;
    /// <summary>Parameter und ggf. Rückgabetyp des Ereignisses AEventName von AComponentClass,
    /// z. B. "(Sender: TObject)", aus der Deklaration des Ereignistyps im Index.</summary>
    class function EventTail(const AIndex: ISymbolIndex; const AReadText: TMemberReadText;
      const AComponentClass, AEventName: string; out ATail: string): Boolean; static;
    /// <summary>"default 5", "default False (implizit)", "nodefault", dazu "stored …"; '' ohne Angabe.</summary>
    class function DefaultText(const AMember: TPublishedMember): string; static;
    /// <summary>Markdown-Abschnitt für den Hover; '' ohne Mitglieder.</summary>
    class function ToMarkdown(const AMembers: TArray<TPublishedMember>): string; overload; static;
    /// <summary>Wie oben, davor die Standard-Property (aus DefaultProperty), wenn nicht ''.</summary>
    class function ToMarkdown(const AMembers: TArray<TPublishedMember>;
      const ADefaultProperty: string): string; overload; static;
    /// <summary>atlas.published für den Tooltip (#110): {"members": [{"name", "type", "default", "defaultKind"
    /// (explicit, implicit, nodefault), "stored", "declaringClass", "publishedIn", "event"}], "defaultProperty"};
    /// leere Angaben fehlen. nil ohne Mitglieder und Standard-Property; sonst gehört das Objekt dem Aufrufer.
    /// </summary>
    class function ToJson(const AMembers: TArray<TPublishedMember>; const ADefaultProperty: string): TJSONObject;
      static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Text.Lines;

const
  BooleanTypes: array[0..3] of string = ('Boolean', 'ByteBool', 'WordBool', 'LongBool');
  IntegerTypes: array[0..15] of string = ('Integer', 'Cardinal', 'ShortInt', 'SmallInt', 'LongInt', 'Int64', 'Byte',
    'Word', 'LongWord', 'UInt64', 'NativeInt', 'NativeUInt', 'Int8', 'Int16', 'Int32', 'UInt32');
  /// <summary>Höchstens so viele Aliase folgt die Ereigniserkennung.</summary>
  MaxAliases = 8;

function ShortName(const AName: string): string;
begin
  // Qualifizierte Namen (Vcl.Controls.TControl) auf den Typnamen kürzen.
  Result := AName;
  if LastDelimiter('.', Result) > 0 then
  begin
    Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
  end;
end;

function FindClass(const AIndex: ISymbolIndex; const AName: string; out ALocation: TSymbolLocation): Boolean;
var
  Location: TSymbolLocation;
begin
  for Location in AIndex.FindSymbols(ShortName(AName)) do
  begin
    if (Location.Symbol.Kind = TIndexSymbolKind.ClassType) and (Location.Symbol.Container = '') then
    begin
      ALocation := Location;
      Exit(True);
    end;
  end;
  Result := False;
end;

function FindTypeDecl(ANode: TSyntaxNode; const AName: string): TSyntaxNode;
var
  Index: Integer;
begin
  if (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, AName) and
    (ANode.FindChild(TSyntaxKind.ClassType) <> nil) then
  begin
    Exit(ANode);
  end;
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    if ANode.Children[Index].Kind in [TSyntaxKind.UnitFile, TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile,
      TSyntaxKind.PackageFile, TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection,
      TSyntaxKind.TypeSection, TSyntaxKind.TypeDecl] then
    begin
      Result := FindTypeDecl(ANode.Children[Index], AName);
      if Result <> nil then
      begin
        Exit;
      end;
    end;
  end;
  Result := nil;
end;

/// <summary>Index des passenden ";" auf oberster Klammerebene ab AStart.</summary>
function DeclarationEnd(const AText: string; AStart: Integer): Integer;
var
  Depth: Integer;
begin
  Depth := 0;
  Result := AStart;
  while Result <= Length(AText) do
  begin
    case AText[Result] of
      '(', '[':
        Inc(Depth);
      ')', ']':
        Dec(Depth);
      ';':
        if Depth = 0 then
        begin
          Exit;
        end;
      '''':
        begin
          Inc(Result);
          while (Result <= Length(AText)) and (AText[Result] <> '''') do
          begin
            Inc(Result);
          end;
        end;
    end;
    Inc(Result);
  end;
end;

type
  TWord = record
    Text: string;
    Start: Integer;
    Stop: Integer;
  end;

/// <summary>Bezeichner auf oberster Klammerebene ab AStart, ohne Strings.</summary>
function TopWords(const AText: string; AStart: Integer): TArray<TWord>;
var
  Index, Depth, First: Integer;
  Item: TWord;
begin
  Result := nil;
  Depth := 0;
  Index := AStart;
  while Index <= Length(AText) do
  begin
    case AText[Index] of
      '(', '[':
        Inc(Depth);
      ')', ']':
        Dec(Depth);
      '''':
        begin
          Inc(Index);
          while (Index <= Length(AText)) and (AText[Index] <> '''') do
          begin
            Inc(Index);
          end;
        end;
      'A'..'Z', 'a'..'z', '_':
        begin
          First := Index;
          while (Index < Length(AText)) and CharInSet(AText[Index + 1], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
          begin
            Inc(Index);
          end;
          if Depth = 0 then
          begin
            Item.Text := Copy(AText, First, Index - First + 1);
            Item.Start := First;
            Item.Stop := Index + 1;
            Result := Result + [Item];
          end;
        end;
    end;
    Inc(Index);
  end;
end;

type
  TSpecifiers = record
    DefaultKind: TPublishedDefaultKind;
    DefaultValue: string;
    Stored: string;
    /// <summary>"; default;" hinter einer Array-Property.</summary>
    ArrayDefault: Boolean;
  end;

const
  SpecifierWords: array[0..9] of string = ('read', 'write', 'stored', 'default', 'nodefault', 'implements', 'index',
    'readonly', 'writeonly', 'dispid');

/// <summary>default, nodefault und stored aus "property Name…: Typ read … stored … default …; default;".</summary>
function ReadSpecifiers(const ADeclaration, AName: string): TSpecifiers;
var
  Words: TArray<TWord>;
  Index, Next, Stop, Start, Finish: Integer;
  Keyword, Value: string;
begin
  Result := Default(TSpecifiers);
  // Ab dem Namen: "Default" als Property-Name zählt nicht als Angabe.
  Start := Pos(LowerCase(AName), LowerCase(ADeclaration));
  if Start = 0 then
  begin
    Start := 1;
  end;
  Inc(Start, Length(AName));
  Stop := DeclarationEnd(ADeclaration, Start);
  Words := TopWords(Copy(ADeclaration, 1, Stop - 1), Start);
  for Index := 0 to High(Words) do
  begin
    Keyword := LowerCase(Words[Index].Text);
    if Keyword = 'nodefault' then
    begin
      Result.DefaultKind := TPublishedDefaultKind.NoDefault;
      Continue;
    end;
    if (Keyword <> 'default') and (Keyword <> 'stored') then
    begin
      Continue;
    end;
    // Wert bis zur nächsten Angabe oder zum Ende.
    Next := Index + 1;
    while (Next <= High(Words)) and (IndexText(Words[Next].Text, SpecifierWords) < 0) do
    begin
      Inc(Next);
    end;
    Finish := Stop;
    if Next <= High(Words) then
    begin
      Finish := Words[Next].Start;
    end;
    Value := Trim(Copy(ADeclaration, Words[Index].Stop, Finish - Words[Index].Stop));
    if Keyword = 'stored' then
    begin
      Result.Stored := Value;
    end
    else
    begin
      Result.DefaultKind := TPublishedDefaultKind.Explicit;
      Result.DefaultValue := Value;
    end;
  end;
  Value := Trim(Copy(ADeclaration, Stop + 1, MaxInt));
  Result.ArrayDefault := SameText(Value, 'default;') or SameText(Value, 'default');
end;

/// <summary>Text der Typdeklaration nach dem Namen bis zum ";" ("= procedure(Sender: TObject) of object").</summary>
function TypeDeclaration(const AIndex: ISymbolIndex; const AReadText: TMemberReadText; const ATypeName: string;
  out AKind: TIndexSymbolKind; out ADeclaration: string): Boolean;
var
  Location: TSymbolLocation;
  Text: string;
  Start: Integer;
begin
  ADeclaration := '';
  AKind := TIndexSymbolKind.TypeAlias;
  if (AIndex = nil) or not Assigned(AReadText) then
  begin
    Exit(False);
  end;
  for Location in AIndex.FindSymbols(ShortName(ATypeName)) do
  begin
    if (Location.Symbol.Container = '') and (Location.Symbol.Kind in [TIndexSymbolKind.TypeAlias,
      TIndexSymbolKind.EnumType, TIndexSymbolKind.ClassType, TIndexSymbolKind.RecordType,
      TIndexSymbolKind.InterfaceType, TIndexSymbolKind.ObjectType]) and AReadText(Location.FileName, Text) then
    begin
      // 1-basierter Index im Text; Zeichen hinter dem Zeilenende zählen als Zeilenende.
      Start := TLineTable.Build(Text).OffsetAt(Location.Symbol.SelectionRange.EndPos) + 1;
      ADeclaration := Trim(Copy(Text, Start, DeclarationEnd(Text, Start) - Start));
      AKind := Location.Symbol.Kind;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>"= TNotifyEvent" bzw. "= type Vcl.Controls.TNotifyEvent" → Zielname; '' bei anderem Text.</summary>
function AliasTarget(const ADeclaration: string): string;
var
  Text: string;
  Index: Integer;
begin
  Result := '';
  Text := Trim(ADeclaration);
  if not StartsText('=', Text) then
  begin
    Exit;
  end;
  Text := Trim(Copy(Text, 2, MaxInt));
  if StartsText('type ', Text) then
  begin
    Text := Trim(Copy(Text, 6, MaxInt));
  end;
  for Index := 1 to Length(Text) do
  begin
    if not CharInSet(Text[Index], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) then
    begin
      Exit;
    end;
  end;
  Result := Text;
end;

class function TPublishedMembers.IsEventType(const AIndex: ISymbolIndex; const AReadText: TMemberReadText;
  const ATypeName: string): Boolean;
var
  Name, Declaration, Lower: string;
  Kind: TIndexSymbolKind;
  Step: Integer;
begin
  Name := ATypeName;
  for Step := 1 to MaxAliases do
  begin
    if (Name = '') or not TypeDeclaration(AIndex, AReadText, Name, Kind, Declaration) then
    begin
      Break;
    end;
    if Kind <> TIndexSymbolKind.TypeAlias then
    begin
      Exit(False);
    end;
    Lower := LowerCase(Declaration);
    if EndsText('of object', Lower) or StartsText('reference to', Trim(Copy(Lower, 2, MaxInt))) then
    begin
      Exit(True);
    end;
    Name := AliasTarget(Declaration);
  end;
  // Typ nicht im Index (VCL ohne Quellen): nur das bekannte TNotifyEvent.
  Result := (Name <> '') and SameText(ShortName(Name), 'TNotifyEvent');
end;

/// <summary>Anfangswert eines Typs ohne default: False, 0 oder der erste Aufzählungswert; '' sonst.</summary>
function ImplicitDefault(const AIndex: ISymbolIndex; const AReadText: TMemberReadText;
  const ATypeName: string): string;
var
  Name, Declaration: string;
  Kind: TIndexSymbolKind;
  Words: TArray<TWord>;
  Step: Integer;
begin
  Result := '';
  Name := ATypeName;
  for Step := 0 to MaxAliases do
  begin
    if IndexText(ShortName(Name), BooleanTypes) >= 0 then
    begin
      Exit('False');
    end;
    if IndexText(ShortName(Name), IntegerTypes) >= 0 then
    begin
      Exit('0');
    end;
    if (Name = '') or not TypeDeclaration(AIndex, AReadText, Name, Kind, Declaration) then
    begin
      Exit;
    end;
    if Kind = TIndexSymbolKind.EnumType then
    begin
      // "= (alNone, alTop, …)": der erste Wert.
      Words := TopWords(Copy(Declaration, Pos('(', Declaration) + 1, MaxInt), 1);
      if Length(Words) > 0 then
      begin
        Result := Words[0].Text;
      end;
      Exit;
    end;
    if Kind <> TIndexSymbolKind.TypeAlias then
    begin
      Exit;
    end;
    Name := AliasTarget(Declaration);
  end;
end;

type
  TPropertyInfo = record
    TypeName: string;
    Specifiers: TSpecifiers;
    IsPublished: Boolean;
  end;

/// <summary>Properties der Klasse in Quelltextreihenfolge; AArrays: auch Array-Properties.</summary>
procedure ReadProperties(AClass: TSyntaxNode; const AText: string; AArrays: Boolean; ANames: TList<string>;
  AInfos: TDictionary<string, TPropertyInfo>; ADeclarations: TDictionary<string, string>);
var
  Index: Integer;
  Child, TypeNode: TSyntaxNode;
  InPublished: Boolean;
  Info: TPropertyInfo;
  Key, Declaration: string;
begin
  InPublished := True;
  for Index := 0 to AClass.ChildCount - 1 do
  begin
    Child := AClass.Children[Index];
    if Child.Kind = TSyntaxKind.Visibility then
    begin
      InPublished := SameText(Child.Name, 'published');
    end
    else if (Child.Kind = TSyntaxKind.PropertyDecl) and
      ((Child.FindChild(TSyntaxKind.Parameters) = nil) = not AArrays) then
    begin
      Key := LowerCase(Child.Name);
      if AInfos.ContainsKey(Key) then
      begin
        Continue;
      end;
      TypeNode := Child.FindChild(TSyntaxKind.TypeReference);
      Info.TypeName := '';
      if TypeNode <> nil then
      begin
        Info.TypeName := TypeNode.Name;
      end;
      Declaration := Copy(AText, Child.StartOffset + 1, Child.EndOffset - Child.StartOffset);
      Info.Specifiers := ReadSpecifiers(Declaration, Child.Name);
      Info.IsPublished := InPublished;
      ANames.Add(Child.Name);
      AInfos.Add(Key, Info);
      if ADeclarations <> nil then
      begin
        ADeclarations.AddOrSetValue(Key, Declaration);
      end;
    end;
  end;
end;

class function TPublishedMembers.Collect(const AIndex: ISymbolIndex; const AClassName: string;
  const AReadText: TMemberReadText): TArray<TPublishedMember>;
var
  Members: TList<TPublishedMember>;
  Positions: TDictionary<string, Integer>;
  Events: TDictionary<string, Boolean>;
  Location: TSymbolLocation;
  ClassName, Text, Key, Name: string;
  Depth, Index: Integer;
  Tree: TSyntaxTree;
  Decl, ClassNode: TSyntaxNode;
  Names: TList<string>;
  Infos: TDictionary<string, TPropertyInfo>;
  Info: TPropertyInfo;
  Member: TPublishedMember;
  IsEvent: Boolean;
begin
  Members := TList<TPublishedMember>.Create;
  Positions := TDictionary<string, Integer>.Create;
  Events := TDictionary<string, Boolean>.Create;
  Names := TList<string>.Create;
  Infos := TDictionary<string, TPropertyInfo>.Create;
  try
    ClassName := AClassName;
    Depth := 0;
    while (ClassName <> '') and (Depth < MaxDepth) and FindClass(AIndex, ClassName, Location) and
      Assigned(AReadText) and AReadText(Location.FileName, Text) do
    begin
      Inc(Depth);
      ClassName := Location.Symbol.Name;
      Tree := TSyntaxTreeCache.Parse(Text);
      try
        Decl := FindTypeDecl(Tree.Root, ClassName);
        if Decl = nil then
        begin
          Break;
        end;
        ClassNode := Decl.FindChild(TSyntaxKind.ClassType);
        Names.Clear;
        Infos.Clear;
        ReadProperties(ClassNode, Text, False, Names, Infos, nil);
      finally
        Tree.Free;
      end;
      for Name in Names do
      begin
        Key := LowerCase(Name);
        Info := Infos[Key];
        if Positions.TryGetValue(Key, Index) then
        begin
          // Schon aus einer abgeleiteten Klasse bekannt: fehlende Angaben ergänzen. Die erste Deklaration
          // mit Typ ist die deklarierende Klasse.
          Member := Members[Index];
          if (Member.TypeName = '') and (Info.TypeName <> '') then
          begin
            Member.TypeName := Info.TypeName;
            Member.DeclaringClass := ClassName;
          end;
          if Member.DefaultKind = TPublishedDefaultKind.None then
          begin
            Member.DefaultKind := Info.Specifiers.DefaultKind;
            Member.DefaultValue := Info.Specifiers.DefaultValue;
          end;
          if Member.Stored = '' then
          begin
            Member.Stored := Info.Specifiers.Stored;
          end;
          Members[Index] := Member;
          Continue;
        end;
        // Nicht published: in abgeleiteten Klassen kann sie noch published werden.
        if not Info.IsPublished then
        begin
          Continue;
        end;
        Member := Default(TPublishedMember);
        Member.Name := Name;
        Member.TypeName := Info.TypeName;
        Member.DefaultKind := Info.Specifiers.DefaultKind;
        Member.DefaultValue := Info.Specifiers.DefaultValue;
        Member.Stored := Info.Specifiers.Stored;
        Member.DeclaringClass := ClassName;
        Member.PublishedIn := ClassName;
        Positions.Add(Key, Members.Count);
        Members.Add(Member);
      end;
      if Length(Location.Symbol.Ancestors) = 0 then
      begin
        Break;
      end;
      ClassName := Location.Symbol.Ancestors[0];
    end;
    // Ereignis am Typ erkennen, implizite Vorgaben ergänzen.
    for Index := 0 to Members.Count - 1 do
    begin
      Member := Members[Index];
      Key := LowerCase(Member.TypeName);
      if not Events.TryGetValue(Key, IsEvent) then
      begin
        IsEvent := (Member.TypeName <> '') and IsEventType(AIndex, AReadText, Member.TypeName);
        Events.Add(Key, IsEvent);
      end;
      Member.IsEvent := IsEvent;
      if not IsEvent and (Member.DefaultKind = TPublishedDefaultKind.None) then
      begin
        Member.DefaultValue := ImplicitDefault(AIndex, AReadText, Member.TypeName);
        if Member.DefaultValue <> '' then
        begin
          Member.DefaultKind := TPublishedDefaultKind.Implicit;
        end;
      end;
      Members[Index] := Member;
    end;
    Result := Members.ToArray;
  finally
    Infos.Free;
    Names.Free;
    Events.Free;
    Positions.Free;
    Members.Free;
  end;
end;

/// <summary>"property Strings[Index: Integer]: string read Get; default;" → "Strings[Index: Integer]: string".</summary>
function DefaultPropertyText(const ADeclaration: string): string;
var
  Words: TArray<TWord>;
  Item: TWord;
  Stop: Integer;
begin
  Result := Trim(ADeclaration);
  if StartsText('property', Result) then
  begin
    Result := Trim(Copy(Result, Length('property') + 1, MaxInt));
  end;
  Stop := DeclarationEnd(Result, 1);
  Words := TopWords(Copy(Result, 1, Stop - 1), 1);
  for Item in Words do
  begin
    if IndexText(Item.Text, SpecifierWords) >= 0 then
    begin
      Stop := Item.Start;
      Break;
    end;
  end;
  Result := Trim(Copy(Result, 1, Stop - 1));
end;

class function TPublishedMembers.DefaultProperty(const AIndex: ISymbolIndex; const AClassName: string;
  const AReadText: TMemberReadText): string;
var
  Location: TSymbolLocation;
  ClassName, Text, Name: string;
  Depth: Integer;
  Tree: TSyntaxTree;
  Decl: TSyntaxNode;
  Names: TList<string>;
  Infos: TDictionary<string, TPropertyInfo>;
  Declarations: TDictionary<string, string>;
begin
  Result := '';
  Names := TList<string>.Create;
  Infos := TDictionary<string, TPropertyInfo>.Create;
  Declarations := TDictionary<string, string>.Create;
  try
    ClassName := AClassName;
    Depth := 0;
    while (ClassName <> '') and (Depth < MaxDepth) and FindClass(AIndex, ClassName, Location) and
      Assigned(AReadText) and AReadText(Location.FileName, Text) do
    begin
      Inc(Depth);
      Tree := TSyntaxTreeCache.Parse(Text);
      try
        Decl := FindTypeDecl(Tree.Root, Location.Symbol.Name);
        if Decl = nil then
        begin
          Break;
        end;
        Names.Clear;
        Infos.Clear;
        Declarations.Clear;
        ReadProperties(Decl.FindChild(TSyntaxKind.ClassType), Text, True, Names, Infos, Declarations);
      finally
        Tree.Free;
      end;
      for Name in Names do
      begin
        if Infos[LowerCase(Name)].Specifiers.ArrayDefault then
        begin
          Exit(DefaultPropertyText(Declarations[LowerCase(Name)]));
        end;
      end;
      if Length(Location.Symbol.Ancestors) = 0 then
      begin
        Break;
      end;
      ClassName := Location.Symbol.Ancestors[0];
    end;
  finally
    Declarations.Free;
    Infos.Free;
    Names.Free;
  end;
end;

/// <summary>"procedure(Sender: TObject) of object" → "(Sender: TObject)".</summary>
function TailOfType(const ADeclaration: string): string;
var
  Lower: string;
  Start, Stop: Integer;
begin
  Result := '';
  Lower := LowerCase(ADeclaration);
  Start := Pos('procedure', Lower);
  if Start > 0 then
  begin
    Inc(Start, Length('procedure'));
  end
  else
  begin
    Start := Pos('function', Lower);
    if Start = 0 then
    begin
      Exit;
    end;
    Inc(Start, Length('function'));
  end;
  Stop := DeclarationEnd(ADeclaration, Start);
  Result := Trim(Copy(ADeclaration, Start, Stop - Start));
  if EndsText('of object', Result) then
  begin
    Result := Trim(Copy(Result, 1, Length(Result) - Length('of object')));
  end;
end;

class function TPublishedMembers.EventTail(const AIndex: ISymbolIndex; const AReadText: TMemberReadText;
  const AComponentClass, AEventName: string; out ATail: string): Boolean;
var
  Member: TPublishedMember;
  TypeName, Declaration: string;
  Kind: TIndexSymbolKind;
begin
  ATail := '';
  TypeName := '';
  if AIndex <> nil then
  begin
    for Member in Collect(AIndex, AComponentClass, AReadText) do
    begin
      if SameText(Member.Name, AEventName) then
      begin
        TypeName := Member.TypeName;
        Break;
      end;
    end;
  end;
  if TypeName = '' then
  begin
    Exit(False);
  end;
  if TypeDeclaration(AIndex, AReadText, TypeName, Kind, Declaration) then
  begin
    ATail := TailOfType(Declaration + ';');
    if ATail <> '' then
    begin
      Exit(True);
    end;
  end;
  if SameText(ShortName(TypeName), 'TNotifyEvent') then
  begin
    ATail := NotifyTail;
  end;
  Result := ATail <> '';
end;

class function TPublishedMembers.DefaultText(const AMember: TPublishedMember): string;
begin
  case AMember.DefaultKind of
    TPublishedDefaultKind.Explicit:
      Result := 'default ' + AMember.DefaultValue;
    TPublishedDefaultKind.Implicit:
      Result := 'default ' + AMember.DefaultValue + ' (implizit)';
    TPublishedDefaultKind.NoDefault:
      Result := 'nodefault';
  else
    Result := '';
  end;
  if AMember.Stored <> '' then
  begin
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + 'stored ' + AMember.Stored;
  end;
end;

function MemberLine(const AMember: TPublishedMember): string;
begin
  Result := '- `' + AMember.Name + '`';
  if AMember.TypeName <> '' then
  begin
    Result := Result + ': `' + AMember.TypeName + '`';
  end;
  case AMember.DefaultKind of
    TPublishedDefaultKind.Explicit:
      Result := Result + ' = `' + AMember.DefaultValue + '`';
    TPublishedDefaultKind.Implicit:
      Result := Result + ' = `' + AMember.DefaultValue + '` (implizit)';
    TPublishedDefaultKind.NoDefault:
      Result := Result + ' · nodefault';
    TPublishedDefaultKind.None: ;
  end;
  if AMember.Stored <> '' then
  begin
    Result := Result + ' · stored `' + AMember.Stored + '`';
  end;
end;

function Section(const ATitle: string; const AMembers: TArray<TPublishedMember>; AEvents, ACompact: Boolean): string;
var
  Member: TPublishedMember;
  Classes: TList<string>;
  CurrentClass, Names: string;
  Count: Integer;
begin
  Result := '';
  Classes := TList<string>.Create;
  try
    // Nach deklarierender Klasse gruppiert, in der Reihenfolge der Ableitung (erstes Auftreten).
    Count := 0;
    for Member in AMembers do
    begin
      if Member.IsEvent = AEvents then
      begin
        Inc(Count);
        if Classes.IndexOf(LowerCase(Member.DeclaringClass)) < 0 then
        begin
          Classes.Add(LowerCase(Member.DeclaringClass));
        end;
      end;
    end;
    if Count = 0 then
    begin
      Exit;
    end;
    Result := Format('**%s** (%d)', [ATitle, Count]);
    for CurrentClass in Classes do
    begin
      Names := '';
      for Member in AMembers do
      begin
        if (Member.IsEvent <> AEvents) or not SameText(Member.DeclaringClass, CurrentClass) then
        begin
          Continue;
        end;
        if Names = '' then
        begin
          Result := Result + #10#10 + '*' + Member.DeclaringClass + '*';
        end;
        if ACompact then
        begin
          if Names <> '' then
          begin
            Names := Names + ', ';
          end;
          Names := Names + Member.Name;
        end
        else
        begin
          Result := Result + #10 + MemberLine(Member);
          Names := Member.Name;
        end;
      end;
      if ACompact then
      begin
        Result := Result + #10 + Names;
      end;
    end;
  finally
    Classes.Free;
  end;
end;

class function TPublishedMembers.ToMarkdown(const AMembers: TArray<TPublishedMember>): string;
begin
  Result := ToMarkdown(AMembers, '');
end;

class function TPublishedMembers.ToMarkdown(const AMembers: TArray<TPublishedMember>;
  const ADefaultProperty: string): string;
var
  Compact: Boolean;
  Properties, Events, Part: string;
begin
  Compact := Length(AMembers) > CompactLimit;
  Properties := Section('Published-Properties', AMembers, False, Compact);
  Events := Section('Ereignisse', AMembers, True, Compact);
  Result := '';
  if ADefaultProperty <> '' then
  begin
    Result := '**Standard-Property:** `' + ADefaultProperty + '`';
  end;
  for Part in TArray<string>.Create(Properties, Events) do
  begin
    if Part <> '' then
    begin
      if Result <> '' then
      begin
        Result := Result + #10#10;
      end;
      Result := Result + Part;
    end;
  end;
end;

class function TPublishedMembers.ToJson(const AMembers: TArray<TPublishedMember>;
  const ADefaultProperty: string): TJSONObject;
const
  KindNames: array[TPublishedDefaultKind] of string = ('', 'explicit', 'implicit', 'nodefault');
var
  Member: TPublishedMember;
  Items: TJSONArray;
  Item: TJSONObject;
begin
  if (Length(AMembers) = 0) and (ADefaultProperty = '') then
  begin
    Exit(nil);
  end;
  Result := TJSONObject.Create;
  Items := TJSONArray.Create;
  Result.AddPair('members', Items);
  for Member in AMembers do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('name', Member.Name);
    if Member.TypeName <> '' then
    begin
      Item.AddPair('type', Member.TypeName);
    end;
    if Member.DefaultValue <> '' then
    begin
      Item.AddPair('default', Member.DefaultValue);
    end;
    if KindNames[Member.DefaultKind] <> '' then
    begin
      Item.AddPair('defaultKind', KindNames[Member.DefaultKind]);
    end;
    if Member.Stored <> '' then
    begin
      Item.AddPair('stored', Member.Stored);
    end;
    if Member.DeclaringClass <> '' then
    begin
      Item.AddPair('declaringClass', Member.DeclaringClass);
    end;
    if Member.PublishedIn <> '' then
    begin
      Item.AddPair('publishedIn', Member.PublishedIn);
    end;
    if Member.IsEvent then
    begin
      Item.AddPair('event', TJSONTrue.Create);
    end;
    Items.AddElement(Item);
  end;
  if ADefaultProperty <> '' then
  begin
    Result.AddPair('defaultProperty', ADefaultProperty);
  end;
end;

end.
