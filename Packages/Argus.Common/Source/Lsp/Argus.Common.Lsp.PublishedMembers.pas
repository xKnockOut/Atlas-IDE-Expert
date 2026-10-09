unit Argus.Common.Lsp.PublishedMembers;

// published-Properties und Ereignisse einer Komponentenklasse für den Hover,
// inklusive geerbter, mit Typ, default-Wert und deklarierender Klasse.
//
// Die Klassen werden über den Symbolindex gefunden und ihre Deklaration aus
// dem Quelltext gelesen, weil der Index keine Sichtbarkeiten speichert.
// Mitglieder vor dem ersten Sichtbarkeitsabschnitt gelten als published
// (Komponenten werden mit {$M+} übersetzt). Eine Neudeklaration ohne Typ
// (property Caption;) macht eine geerbte Property published; Typ und
// default kommen dann vom Vorfahren. Ereignisse sind Properties, deren Name
// mit On beginnt oder deren Typ auf Event endet.

interface

uses
  System.SysUtils,
  Argus.Common.Index.Contract;

type
  TMemberReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  TPublishedMember = record
    Name: string;
    TypeName: string;
    /// <summary>Text nach default, '' ohne Angabe.</summary>
    DefaultValue: string;
    /// <summary>Klasse, in der die Property published wird.</summary>
    DeclaringClass: string;
    IsEvent: Boolean;
  end;

  TPublishedMembers = class
  public const
    /// <summary>Ab so vielen Einträgen werden nur noch Namen je Klasse gezeigt.</summary>
    CompactLimit = 40;
    MaxDepth = 32;
    /// <summary>Alle published-Mitglieder, abgeleitete Klassen zuerst.</summary>
    class function Collect(const AIndex: ISymbolIndex; const AClassName: string;
      const AReadText: TMemberReadText): TArray<TPublishedMember>; static;
    /// <summary>Markdown-Abschnitt für den Hover; '' ohne Mitglieder.</summary>
    class function ToMarkdown(const AMembers: TArray<TPublishedMember>): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Pascal.Parser;

function FindClass(const AIndex: ISymbolIndex; const AName: string; out ALocation: TSymbolLocation): Boolean;
var
  Location: TSymbolLocation;
  Name: string;
begin
  // Qualifizierte Namen (Vcl.Controls.TControl) auf den Typnamen kürzen.
  Name := AName;
  if LastDelimiter('.', Name) > 0 then
    Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  for Location in AIndex.FindSymbols(Name) do
    if (Location.Symbol.Kind = TIndexSymbolKind.ClassType) and (Location.Symbol.Container = '') then
    begin
      ALocation := Location;
      Exit(True);
    end;
  Result := False;
end;

function FindTypeDecl(ANode: TSyntaxNode; const AName: string): TSyntaxNode;
var
  Index: Integer;
begin
  if (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, AName) and
    (ANode.FindChild(TSyntaxKind.ClassType) <> nil) then
    Exit(ANode);
  for Index := 0 to ANode.ChildCount - 1 do
    if ANode.Children[Index].Kind in [TSyntaxKind.UnitFile, TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile,
      TSyntaxKind.PackageFile, TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection,
      TSyntaxKind.TypeSection, TSyntaxKind.TypeDecl] then
    begin
      Result := FindTypeDecl(ANode.Children[Index], AName);
      if Result <> nil then
        Exit;
    end;
  Result := nil;
end;

/// <summary>Wert hinter "default" im Deklarationstext; '' ohne.</summary>
function DefaultOf(const ADeclaration: string): string;
var
  Lower: string;
  Index, Stop: Integer;
begin
  Result := '';
  Lower := LowerCase(ADeclaration);
  Index := Pos(' default ', Lower);
  if Index = 0 then
    Exit;
  Result := Copy(ADeclaration, Index + Length(' default '), MaxInt);
  Stop := Pos(';', Result);
  if Stop > 0 then
    Result := Copy(Result, 1, Stop - 1);
  Result := Trim(Result);
end;

function IsEventProperty(const AName, ATypeName: string): Boolean;
begin
  Result := ((Length(AName) > 2) and SameText(Copy(AName, 1, 2), 'On') and CharInSet(AName[3], ['A'..'Z'])) or
    SameText(Copy(ATypeName, Length(ATypeName) - 4, 5), 'Event');
end;

type
  TPropertyInfo = record
    TypeName: string;
    DefaultValue: string;
    IsPublished: Boolean;
  end;

/// <summary>Properties der Klasse in Quelltextreihenfolge.</summary>
procedure ReadProperties(AClass: TSyntaxNode; const AText: string; ANames: TList<string>;
  AInfos: TDictionary<string, TPropertyInfo>);
var
  Index: Integer;
  Child, TypeNode: TSyntaxNode;
  InPublished: Boolean;
  Info: TPropertyInfo;
  Key: string;
begin
  InPublished := True;
  for Index := 0 to AClass.ChildCount - 1 do
  begin
    Child := AClass.Children[Index];
    if Child.Kind = TSyntaxKind.Visibility then
      InPublished := SameText(Child.Name, 'published')
    else if (Child.Kind = TSyntaxKind.PropertyDecl) and (Child.FindChild(TSyntaxKind.Parameters) = nil) then
    begin
      Key := LowerCase(Child.Name);
      if AInfos.ContainsKey(Key) then
        Continue;
      TypeNode := Child.FindChild(TSyntaxKind.TypeReference);
      Info.TypeName := '';
      if TypeNode <> nil then
        Info.TypeName := TypeNode.Name;
      Info.DefaultValue := DefaultOf(Copy(AText, Child.StartOffset + 1, Child.EndOffset - Child.StartOffset));
      Info.IsPublished := InPublished;
      ANames.Add(Child.Name);
      AInfos.Add(Key, Info);
    end;
  end;
end;

class function TPublishedMembers.Collect(const AIndex: ISymbolIndex; const AClassName: string;
  const AReadText: TMemberReadText): TArray<TPublishedMember>;
var
  Members: TList<TPublishedMember>;
  Positions: TDictionary<string, Integer>;
  Location: TSymbolLocation;
  ClassName, Text, Key, Name: string;
  Depth, Index: Integer;
  Tree: TSyntaxTree;
  Decl, ClassNode: TSyntaxNode;
  Names: TList<string>;
  Infos: TDictionary<string, TPropertyInfo>;
  Info: TPropertyInfo;
  Member: TPublishedMember;
begin
  Members := TList<TPublishedMember>.Create;
  Positions := TDictionary<string, Integer>.Create;
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
      Tree := TPascalParser.Parse(Text);
      try
        Decl := FindTypeDecl(Tree.Root, ClassName);
        if Decl = nil then
          Break;
        ClassNode := Decl.FindChild(TSyntaxKind.ClassType);
        Names.Clear;
        Infos.Clear;
        ReadProperties(ClassNode, Text, Names, Infos);
      finally
        Tree.Free;
      end;
      for Name in Names do
      begin
        Key := LowerCase(Name);
        Info := Infos[Key];
        if Positions.TryGetValue(Key, Index) then
        begin
          // Schon aus einer abgeleiteten Klasse bekannt: fehlende Angaben ergänzen.
          Member := Members[Index];
          if Member.TypeName = '' then
            Member.TypeName := Info.TypeName;
          if Member.DefaultValue = '' then
            Member.DefaultValue := Info.DefaultValue;
          Member.IsEvent := IsEventProperty(Member.Name, Member.TypeName);
          Members[Index] := Member;
          Continue;
        end;
        // Nicht published: in abgeleiteten Klassen kann sie noch published werden.
        Member.Name := Name;
        Member.TypeName := Info.TypeName;
        Member.DefaultValue := Info.DefaultValue;
        Member.DeclaringClass := ClassName;
        Member.IsEvent := IsEventProperty(Name, Info.TypeName);
        if Info.IsPublished then
        begin
          Positions.Add(Key, Members.Count);
          Members.Add(Member);
        end;
      end;
      if Length(Location.Symbol.Ancestors) = 0 then
        Break;
      ClassName := Location.Symbol.Ancestors[0];
    end;
    Result := Members.ToArray;
  finally
    Infos.Free;
    Names.Free;
    Positions.Free;
    Members.Free;
  end;
end;

function MemberLine(const AMember: TPublishedMember): string;
begin
  Result := '- `' + AMember.Name + '`';
  if AMember.TypeName <> '' then
    Result := Result + ': `' + AMember.TypeName + '`';
  if AMember.DefaultValue <> '' then
    Result := Result + ' = `' + AMember.DefaultValue + '`';
end;

function Section(const ATitle: string; const AMembers: TArray<TPublishedMember>; AEvents, ACompact: Boolean): string;
var
  Member: TPublishedMember;
  CurrentClass, Names: string;
  Count: Integer;
begin
  Result := '';
  Count := 0;
  for Member in AMembers do
    if Member.IsEvent = AEvents then
      Inc(Count);
  if Count = 0 then
    Exit;
  Result := Format('**%s** (%d)', [ATitle, Count]);
  CurrentClass := '';
  Names := '';
  // Nach deklarierender Klasse gruppiert, in der Reihenfolge der Ableitung.
  for Member in AMembers do
  begin
    if Member.IsEvent <> AEvents then
      Continue;
    if not SameText(Member.DeclaringClass, CurrentClass) then
    begin
      if ACompact and (Names <> '') then
        Result := Result + #10 + Names;
      CurrentClass := Member.DeclaringClass;
      Result := Result + #10#10 + '*' + CurrentClass + '*';
      Names := '';
    end;
    if ACompact then
    begin
      if Names <> '' then
        Names := Names + ', ';
      Names := Names + Member.Name;
    end
    else
      Result := Result + #10 + MemberLine(Member);
  end;
  if ACompact and (Names <> '') then
    Result := Result + #10 + Names;
end;

class function TPublishedMembers.ToMarkdown(const AMembers: TArray<TPublishedMember>): string;
var
  Compact: Boolean;
  Properties, Events: string;
begin
  Compact := Length(AMembers) > CompactLimit;
  Properties := Section('Published-Properties', AMembers, False, Compact);
  Events := Section('Ereignisse', AMembers, True, Compact);
  Result := Properties;
  if (Result <> '') and (Events <> '') then
    Result := Result + #10#10;
  Result := Result + Events;
end;

end.
