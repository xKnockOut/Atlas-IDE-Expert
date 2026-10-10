unit Argus.Common.Mcp.IndexTools;

// Lesende MCP-Werkzeuge auf dem Symbolindex (#48). Die Ergebnisse sind kurzer
// Text für ein Sprachmodell: Fundstellen mit Datei und Zeile (1-basiert) statt
// ganzer Quelltexte, damit das Modell Dateien nicht vollständig lesen muss.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Argus.Common.Index.Contract;

type
  TMcpReadText = reference to function(const AFileName: string; out AText: string): Boolean;
  /// <summary>Package (.dpk), das die Unit in contains führt; '' ohne.</summary>
  TMcpPackageOf = reference to function(const AUnitName: string): string;

  /// <summary>Eintrag aus RegisterComponents('Seite', [TKlasse, …]).</summary>
  TComponentRegistration = record
    Page: string;
    ClassName: string;
  end;

  TMcpIndexTools = class
  public const
    MaxResults = 50;
    MaxDeclarations = 5;
    MaxDepth = 12;
  private
    FIndex: ISymbolIndex;
    FReadText: TMcpReadText;
    FPackageOf: TMcpPackageOf;
    function TypeMatches(const AName: string): TArray<TSymbolLocation>;
    procedure AddDescendants(ALines: TStrings; const ATypeName: string; ADepth: Integer;
      AVisited: TDictionary<string, Boolean>);
  public
    /// <summary>AReadText darf nil sein; dann liefert Declaration nur Fundstellen.</summary>
    constructor Create(const AIndex: ISymbolIndex; const AReadText: TMcpReadText);
    /// <summary>Symbole zu "Bar", "TFoo.Bar" oder "Unit.TFoo.Bar".</summary>
    function Matches(const AName: string): TArray<TSymbolLocation>;
    /// <summary>Symbole nach Name ("Bar" oder "TFoo.Bar"); ohne exakten Treffer Teilstring-Suche.</summary>
    function FindSymbol(const AQuery: string): string;
    /// <summary>Quelltext der Deklaration(en) mit Fundstelle.</summary>
    function Declaration(const AQuery: string): string;
    /// <summary>Vorfahren (bis zur Wurzel) und Nachfahren (rekursiv) eines Typs.</summary>
    function TypeHierarchy(const ATypeName: string): string;
    /// <summary>uses-Listen und Symbole einer Unit (Name oder Dateipfad).</summary>
    function UnitOutline(const AUnitOrFile: string): string;
    /// <summary>published-Properties mit Typ und Default, Ereignisse mit Signatur, Vorfahren,
    /// Palettenseite und Package einer Komponentenklasse (#113).</summary>
    function ComponentInfo(const AClassName: string): string;
    /// <summary>Alle RegisterComponents-Aufrufe in AText.</summary>
    class function Registrations(const AText: string): TArray<TComponentRegistration>; static;
    /// <summary>Führt die contains-Klausel von ADpkText die Unit AUnitName?</summary>
    class function PackageContains(const ADpkText, AUnitName: string): Boolean; static;
    /// <summary>Für ComponentInfo; ohne Zuweisung ist das Package unbekannt.</summary>
    property PackageOf: TMcpPackageOf read FPackageOf write FPackageOf;
    /// <summary>Komponentenbaum mit Typen, Ereignissen und Eigenschaften eines Formulars.</summary>
    class function DfmInfo(const AText: string): string; static;
    class function KindName(AKind: TIndexSymbolKind): string; static;
    class function Location(const ALocation: TSymbolLocation): string; static;
  end;

implementation

uses
  System.StrUtils,
  Argus.Common.Lsp.PublishedMembers,
  Argus.Common.Dfm.FormInfo;

const
  TypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType, TIndexSymbolKind.EnumType,
    TIndexSymbolKind.TypeAlias];

function JoinLines(ALines: TStrings): string;
begin
  Result := TrimRight(ALines.Text);
end;

{ TMcpIndexTools }

constructor TMcpIndexTools.Create(const AIndex: ISymbolIndex; const AReadText: TMcpReadText);
begin
  inherited Create;
  FIndex := AIndex;
  FReadText := AReadText;
end;

class function TMcpIndexTools.KindName(AKind: TIndexSymbolKind): string;
begin
  case AKind of
    TIndexSymbolKind.ClassType: Result := 'Klasse';
    TIndexSymbolKind.ObjectType: Result := 'Objekttyp';
    TIndexSymbolKind.RecordType: Result := 'Record';
    TIndexSymbolKind.InterfaceType: Result := 'Interface';
    TIndexSymbolKind.HelperType: Result := 'Helfer';
    TIndexSymbolKind.EnumType: Result := 'Aufzählung';
    TIndexSymbolKind.TypeAlias: Result := 'Typ';
    TIndexSymbolKind.EnumMember: Result := 'Aufzählungswert';
    TIndexSymbolKind.Constant: Result := 'Konstante';
    TIndexSymbolKind.Variable: Result := 'Variable';
    TIndexSymbolKind.Field: Result := 'Feld';
    TIndexSymbolKind.Property_: Result := 'Property';
    TIndexSymbolKind.Method: Result := 'Methode';
    TIndexSymbolKind.Constructor_: Result := 'Konstruktor';
  else
    Result := 'Routine';
  end;
end;

class function TMcpIndexTools.Location(const ALocation: TSymbolLocation): string;
begin
  Result := Format('%s:%d', [ALocation.FileName, ALocation.Symbol.SelectionRange.StartPos.Line + 1]);
end;

function Describe(const ALocation: TSymbolLocation): string;
begin
  Result := Format('%s (%s', [ALocation.Symbol.QualifiedName, TMcpIndexTools.KindName(ALocation.Symbol.Kind)]);
  if ALocation.Symbol.TypeName <> '' then
    Result := Result + ': ' + ALocation.Symbol.TypeName;
  if not ALocation.Symbol.InInterface then
    Result := Result + ', nur implementation';
  Result := Result + Format(') – Unit %s, %s', [ALocation.UnitName, TMcpIndexTools.Location(ALocation)]);
end;

function TMcpIndexTools.Matches(const AName: string): TArray<TSymbolLocation>;
var
  Query, Container, Name: string;
  Dot: Integer;
  Found: TList<TSymbolLocation>;
  Location: TSymbolLocation;
begin
  Query := Trim(AName);
  Name := Query;
  Container := '';
  Dot := LastDelimiter('.', Name);
  if Dot > 0 then
  begin
    Container := Copy(Name, 1, Dot - 1);
    // Unit-Präfix (System.SysUtils.TFoo.Bar) zählt nicht zum Container.
    if LastDelimiter('.', Container) > 0 then
      Container := Copy(Container, LastDelimiter('.', Container) + 1, MaxInt);
    Name := Copy(Name, Dot + 1, MaxInt);
  end;
  Found := TList<TSymbolLocation>.Create;
  try
    for Location in FIndex.FindSymbols(Name) do
      if (Container = '') or SameText(Location.Symbol.Container, Container) or
        ((Dot > 0) and SameText(Location.UnitName, Copy(Query, 1, Dot - 1))) then
        Found.Add(Location);
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

function TMcpIndexTools.TypeMatches(const AName: string): TArray<TSymbolLocation>;
var
  Location: TSymbolLocation;
  Found: TList<TSymbolLocation>;
begin
  Found := TList<TSymbolLocation>.Create;
  try
    for Location in Matches(AName) do
      if Location.Symbol.Kind in TypeKinds then
        Found.Add(Location);
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

function TMcpIndexTools.FindSymbol(const AQuery: string): string;
var
  Lines: TStringList;
  Found: TArray<TSymbolLocation>;
  Location: TSymbolLocation;
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
  Count: Integer;
begin
  Lines := TStringList.Create;
  try
    Found := Matches(AQuery);
    if Length(Found) > 0 then
    begin
      Count := 0;
      for Location in Found do
      begin
        Lines.Add(Describe(Location));
        Inc(Count);
        if Count >= MaxResults then
        begin
          Lines.Add(Format('… %d weitere', [Length(Found) - Count]));
          Break;
        end;
      end;
      Exit(JoinLines(Lines));
    end;
    // Kein exakter Treffer: Teilstring im Namen, z. B. "Customer" findet TCustomerList.
    Count := 0;
    for UnitIndex in FIndex.Units do
      for Symbol in UnitIndex.Symbols do
        if ContainsText(Symbol.Name, AQuery) then
        begin
          if Count >= MaxResults then
          begin
            Lines.Add('… weitere Treffer, Suche genauer fassen');
            Exit(JoinLines(Lines));
          end;
          Location.UnitName := UnitIndex.UnitName;
          Location.FileName := UnitIndex.FileName;
          Location.Symbol := Symbol;
          Lines.Add(Describe(Location));
          Inc(Count);
        end;
    if Lines.Count = 0 then
      Exit(Format('Kein Symbol "%s" im Index (%d Units).', [AQuery, FIndex.UnitCount]));
    Result := 'Kein exakter Treffer, ähnliche Namen:' + sLineBreak + JoinLines(Lines);
  finally
    Lines.Free;
  end;
end;

function TMcpIndexTools.Declaration(const AQuery: string): string;
var
  Lines, Source: TStringList;
  Location: TSymbolLocation;
  Text: string;
  Line, Count: Integer;
begin
  Lines := TStringList.Create;
  Source := TStringList.Create;
  try
    Count := 0;
    for Location in Matches(AQuery) do
    begin
      if Count >= MaxDeclarations then
      begin
        Lines.Add('… weitere Deklarationen, Namen genauer fassen (TFoo.Bar)');
        Break;
      end;
      Inc(Count);
      if Lines.Count > 0 then
        Lines.Add('');
      Lines.Add('// ' + Describe(Location));
      if Assigned(FReadText) and FReadText(Location.FileName, Text) then
      begin
        Source.Text := Text;
        for Line := Location.Symbol.Range.StartPos.Line to Location.Symbol.Range.EndPos.Line do
          if (Line >= 0) and (Line < Source.Count) then
            Lines.Add(Source[Line]);
      end;
    end;
    if Count = 0 then
      Exit(Format('Kein Symbol "%s" im Index.', [AQuery]));
    Result := JoinLines(Lines);
  finally
    Source.Free;
    Lines.Free;
  end;
end;

procedure TMcpIndexTools.AddDescendants(ALines: TStrings; const ATypeName: string; ADepth: Integer;
  AVisited: TDictionary<string, Boolean>);
var
  Location: TSymbolLocation;
  Key: string;
begin
  if ADepth > MaxDepth then
    Exit;
  for Location in FIndex.Descendants(ATypeName) do
  begin
    Key := LowerCase(Location.UnitName + '.' + Location.Symbol.QualifiedName);
    if AVisited.ContainsKey(Key) then
      Continue;
    AVisited.Add(Key, True);
    ALines.Add(StringOfChar(' ', ADepth * 2) + '- ' + Describe(Location));
    AddDescendants(ALines, Location.Symbol.Name, ADepth + 1, AVisited);
  end;
end;

class function TMcpIndexTools.Registrations(const AText: string): TArray<TComponentRegistration>;
const
  Call = 'registercomponents';
var
  Lower, Page, Name: string;
  Start, Index, Close: Integer;
  Entry: TComponentRegistration;
begin
  Result := nil;
  Lower := LowerCase(AText);
  Start := Pos(Call, Lower);
  while Start > 0 do
  begin
    // RegisterComponents('Seite', [TA, TB]);
    Index := PosEx('''', AText, Start + Length(Call));
    Close := PosEx('''', AText, Index + 1);
    if (Index = 0) or (Close = 0) then
      Break;
    Page := Copy(AText, Index + 1, Close - Index - 1);
    Index := PosEx('[', AText, Close);
    Close := PosEx(']', AText, Index + 1);
    if (Index = 0) or (Close = 0) then
      Break;
    for Name in Copy(AText, Index + 1, Close - Index - 1).Split([',']) do
      if Trim(Name) <> '' then
      begin
        Entry.Page := Page;
        Entry.ClassName := Trim(Name);
        Result := Result + [Entry];
      end;
    Start := PosEx(Call, Lower, Close);
  end;
end;

class function TMcpIndexTools.PackageContains(const ADpkText, AUnitName: string): Boolean;
var
  Lower, Name: string;
  Start, Stop: Integer;
  Entry: string;
begin
  Result := False;
  Lower := LowerCase(ADpkText);
  Start := Pos('contains', Lower);
  while (Start > 0) and (((Start > 1) and CharInSet(Lower[Start - 1], ['a'..'z', '0'..'9', '_', '.'])) or
    ((Start + 8 <= Length(Lower)) and CharInSet(Lower[Start + 8], ['a'..'z', '0'..'9', '_']))) do
    Start := PosEx('contains', Lower, Start + 1);
  if Start = 0 then
    Exit;
  Stop := PosEx(';', Lower, Start);
  if Stop = 0 then
    Stop := Length(Lower) + 1;
  Name := LowerCase(AUnitName);
  // Einträge: "Unit" oder "Unit in 'Pfad'", durch Kommas getrennt.
  for Entry in Copy(Lower, Start + 8, Stop - Start - 8).Split([',']) do
    if SameText(Trim(Copy(Trim(Entry), 1, Pos(' ', Trim(Entry) + ' ') - 1)), Name) then
      Exit(True);
end;

function TMcpIndexTools.ComponentInfo(const AClassName: string): string;
var
  Lines: TStringList;
  Found, Parents, Routines: TArray<TSymbolLocation>;
  Current, Routine: TSymbolLocation;
  Members: TArray<TPublishedMember>;
  Member: TPublishedMember;
  Registration: TComponentRegistration;
  Chain: TList<string>;
  Text, Tail, Pages, Package, Line: string;
  ReadText: TMemberReadText;
  Files: TList<string>;
begin
  Found := TypeMatches(AClassName);
  if Length(Found) = 0 then
    Exit(Format('Keine Quellen zu "%s" im Index; nur der Name ist bekannt (z. B. nur als .dcu vorhanden).',
      [AClassName]));
  Lines := TStringList.Create;
  Chain := TList<string>.Create;
  Files := TList<string>.Create;
  try
    Current := Found[0];
    Lines.Add(Describe(Current));
    // Vorfahrenkette über die jeweils erste Basisklasse.
    Line := Current.Symbol.Name;
    while (Length(Current.Symbol.Ancestors) > 0) and (Chain.Count < MaxDepth) and
      not Chain.Contains(LowerCase(Current.Symbol.Ancestors[0])) do
    begin
      Chain.Add(LowerCase(Current.Symbol.Ancestors[0]));
      Line := Line + ' → ' + Current.Symbol.Ancestors[0];
      Parents := TypeMatches(Current.Symbol.Ancestors[0]);
      if Length(Parents) = 0 then
        Break;
      Current := Parents[0];
    end;
    Lines.Add('Vorfahren: ' + Line);
    // Palettenseite: RegisterComponents in der Unit der Klasse und in allen Register-Routinen.
    Files.Add(Found[0].FileName);
    Routines := FIndex.FindSymbols('Register');
    for Routine in Routines do
      if (Routine.Symbol.Container = '') and not Files.Contains(Routine.FileName) then
        Files.Add(Routine.FileName);
    Pages := '';
    if Assigned(FReadText) then
      for Line in Files do
        if FReadText(Line, Text) then
          for Registration in Registrations(Text) do
            if SameText(Registration.ClassName, Found[0].Symbol.Name) and (Pos(Registration.Page, Pages) = 0) then
            begin
              if Pages <> '' then
                Pages := Pages + ', ';
              Pages := Pages + Registration.Page;
            end;
    if Pages = '' then
      Pages := 'keine';
    Lines.Add('Registrierung (Palettenseite): ' + Pages);
    Package := '';
    if Assigned(FPackageOf) then
      Package := FPackageOf(Found[0].UnitName);
    if Package = '' then
      Package := 'unbekannt';
    Lines.Add('Package: ' + Package);
    if not Assigned(FReadText) then
      Exit(JoinLines(Lines));
    ReadText :=
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := FReadText(AFileName, AText);
      end;
    Members := TPublishedMembers.Collect(FIndex, Found[0].Symbol.Name, ReadText);
    Lines.Add('Properties:');
    for Member in Members do
      if not Member.IsEvent then
      begin
        Line := Format('  %s: %s', [Member.Name, Member.TypeName]);
        if Member.DefaultValue <> '' then
          Line := Line + ' default ' + Member.DefaultValue;
        if not SameText(Member.DeclaringClass, Found[0].Symbol.Name) then
          Line := Line + ' (aus ' + Member.DeclaringClass + ')';
        Lines.Add(Line);
      end;
    Lines.Add('Ereignisse:');
    for Member in Members do
      if Member.IsEvent then
      begin
        Line := Format('  %s: %s', [Member.Name, Member.TypeName]);
        if TPublishedMembers.EventTail(FIndex, ReadText, Found[0].Symbol.Name, Member.Name, Tail) then
          Line := Line + ' – Signatur ' + Tail;
        if not SameText(Member.DeclaringClass, Found[0].Symbol.Name) then
          Line := Line + ' (aus ' + Member.DeclaringClass + ')';
        Lines.Add(Line);
      end;
    Result := JoinLines(Lines);
  finally
    Files.Free;
    Chain.Free;
    Lines.Free;
  end;
end;

function TMcpIndexTools.TypeHierarchy(const ATypeName: string): string;
var
  Lines: TStringList;
  Found, Parents: TArray<TSymbolLocation>;
  Current: TSymbolLocation;
  Visited: TDictionary<string, Boolean>;
  Chain: TList<string>;
  Index: Integer;
  Name: string;
begin
  Found := TypeMatches(ATypeName);
  if Length(Found) = 0 then
    Exit(Format('Kein Typ "%s" im Index.', [ATypeName]));
  Lines := TStringList.Create;
  Chain := TList<string>.Create;
  Visited := TDictionary<string, Boolean>.Create;
  try
    Current := Found[0];
    Lines.Add(Describe(Current));
    if Length(Current.Symbol.Ancestors) > 1 then
      Lines.Add('Implementiert/erweitert: ' + string.Join(', ', Copy(Current.Symbol.Ancestors, 1, MaxInt)));
    // Vorfahren über den jeweils ersten Eintrag (Basisklasse bzw. -interface).
    Lines.Add('Vorfahren:');
    while (Length(Current.Symbol.Ancestors) > 0) and (Chain.Count < MaxDepth) do
    begin
      Name := Current.Symbol.Ancestors[0];
      if Chain.Contains(LowerCase(Name)) then
        Break;
      Chain.Add(LowerCase(Name));
      Parents := TypeMatches(Name);
      if Length(Parents) = 0 then
      begin
        Lines.Add('  - ' + Name + ' (nicht im Index)');
        Break;
      end;
      Current := Parents[0];
      Lines.Add('  - ' + Describe(Current));
    end;
    if Chain.Count = 0 then
      Lines.Add('  (keine)');
    Lines.Add('Nachfahren:');
    Index := Lines.Count;
    AddDescendants(Lines, Found[0].Symbol.Name, 1, Visited);
    if Lines.Count = Index then
      Lines.Add('  (keine im Index)');
    if Length(Found) > 1 then
      Lines.Add(Format('Hinweis: %d Typen dieses Namens, gezeigt wird der erste.', [Length(Found)]));
    Result := JoinLines(Lines);
  finally
    Visited.Free;
    Chain.Free;
    Lines.Free;
  end;
end;

function TMcpIndexTools.UnitOutline(const AUnitOrFile: string): string;
var
  UnitIndex: TUnitIndex;
  Lines: TStringList;
  Symbol: TIndexSymbol;
  Indent, Section: string;
  InInterface: Boolean;
begin
  if not FIndex.FindUnit(AUnitOrFile, UnitIndex) and not FIndex.FindFile(AUnitOrFile, UnitIndex) then
    Exit(Format('Unit "%s" nicht im Index.', [AUnitOrFile]));
  Lines := TStringList.Create;
  try
    Lines.Add(Format('unit %s – %s', [UnitIndex.UnitName, UnitIndex.FileName]));
    if Length(UnitIndex.InterfaceUses) > 0 then
      Lines.Add('uses (interface): ' + string.Join(', ', UnitIndex.InterfaceUses));
    if Length(UnitIndex.ImplementationUses) > 0 then
      Lines.Add('uses (implementation): ' + string.Join(', ', UnitIndex.ImplementationUses));
    InInterface := False;
    Section := '';
    for Symbol in UnitIndex.Symbols do
    begin
      if (Section = '') or (Symbol.InInterface <> InInterface) then
      begin
        InInterface := Symbol.InInterface;
        Section := IfThen(InInterface, 'interface', 'implementation');
        Lines.Add(Section + ':');
      end;
      Indent := IfThen(Symbol.Container = '', '  ', '    ');
      Lines.Add(Format('%s%s %s%s – Zeile %d', [Indent, KindName(Symbol.Kind),
        IfThen(Symbol.Container = '', Symbol.Name, Symbol.QualifiedName),
        IfThen(Symbol.TypeName <> '', ': ' + Symbol.TypeName, '') +
        IfThen(Length(Symbol.Ancestors) > 0, '(' + string.Join(', ', Symbol.Ancestors) + ')', ''),
        Symbol.SelectionRange.StartPos.Line + 1]));
    end;
    Result := JoinLines(Lines);
  finally
    Lines.Free;
  end;
end;

class function TMcpIndexTools.DfmInfo(const AText: string): string;
begin
  // Gemeinsam mit dem Hover über Formularfelder (#126).
  Result := TFormInfo.Describe(AText);
end;

end.
