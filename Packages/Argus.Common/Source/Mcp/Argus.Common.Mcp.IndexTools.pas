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

  TMcpIndexTools = class
  public const
    MaxResults = 50;
    MaxDeclarations = 5;
    MaxDepth = 12;
  private
    FIndex: ISymbolIndex;
    FReadText: TMcpReadText;
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
    /// <summary>Komponentenbaum mit Typen, Ereignissen und Eigenschaften eines Formulars.</summary>
    class function DfmInfo(const AText: string): string; static;
    class function KindName(AKind: TIndexSymbolKind): string; static;
    class function Location(const ALocation: TSymbolLocation): string; static;
  end;

implementation

uses
  System.StrUtils,
  Argus.Common.Dfm.Contract,
  Argus.Common.Dfm.Parser;

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

procedure AddDfmObject(ALines: TStrings; AObject: TDfmObject; ADepth: Integer);
var
  Indent, Events, Value: string;
  Prop: TDfmProperty;
  Child: TDfmObject;
begin
  Indent := StringOfChar(' ', ADepth * 2);
  if AObject.Kind = TDfmObjectKind.Item then
    ALines.Add(Indent + '- item')
  else
    ALines.Add(Format('%s- %s: %s%s', [Indent, IfThen(AObject.Name <> '', AObject.Name, '(ohne Namen)'),
      AObject.TypeName, IfThen(AObject.Kind = TDfmObjectKind.Inherited_, ' (geerbt)', '')]));
  Events := '';
  for Prop in AObject.Properties do
    if Prop.IsEvent then
      Events := Events + IfThen(Events <> '', ', ', '') + Prop.Name + ' → ' + Prop.Value
    else
    begin
      Value := StringReplace(Prop.Value, sLineBreak, ' ', [rfReplaceAll]);
      if Length(Value) > 60 then
        Value := Copy(Value, 1, 57) + '...';
      ALines.Add(Format('%s    %s = %s', [Indent, Prop.Name, Value]));
    end;
  if Events <> '' then
    ALines.Add(Indent + '    Ereignisse: ' + Events);
  for Child in AObject.Children do
    AddDfmObject(ALines, Child, ADepth + 1);
end;

class function TMcpIndexTools.DfmInfo(const AText: string): string;
var
  Document: TDfmDocument;
  Lines: TStringList;
  Error: TDfmError;
begin
  Document := TDfmParser.Parse(AText);
  Lines := TStringList.Create;
  try
    if Document.Root = nil then
      Lines.Add('Kein Formular gefunden (binäre DFM-Dateien werden nicht gelesen).')
    else
      AddDfmObject(Lines, Document.Root, 0);
    for Error in Document.Errors do
      Lines.Add(Format('Fehler Zeile %d: %s', [Error.Position.Line + 1, Error.Message]));
    Result := JoinLines(Lines);
  finally
    Lines.Free;
    Document.Free;
  end;
end;

end.
