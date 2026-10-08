unit BDLsp.Common.Lsp.FormSymbols;

// Hover und Gehe zu Definition in Formulardateien (#308):
//   - Property-Name (auch Font.Style und in Collection-Einträgen): Deklaration,
//     Typ, default und deklarierende Klasse; Sprung zur Property
//   - Klassenname (object btnOk: TButton): Klasse mit published-Mitgliedern; Sprung zur Klasse
//   - Aufzählungs- und Mengenwerte (alClient, [fsBold]): Typ und alle Werte; Sprung zum Wert
//   - Ereignis-Handler (OnClick = btnOkClick): Signatur der Methode aus der Unit
// Dazu die Suche nach gespeicherten Werten, die dem default entsprechen
// (Grundlage der Regel dfm-redundant-default). Was sich nicht auflösen lässt
// (Klassen ohne Quellen), ergibt keinen Hover und kein Ziel.

interface

uses
  System.SysUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Dfm.Contract,
  BDLsp.Common.Lsp.PublishedMembers;

type
  /// <summary>Wert in der Formulardatei, der dem default der Property entspricht.</summary>
  TRedundantDefault = record
    /// <summary>Ganze Zeile "Name = Wert".</summary>
    Range: TTextRange;
    PropertyName: string;
    Value: string;
  end;

  TFormSymbols = class
  public
    /// <summary>Markdown für APosition; '' ohne Treffer. AFormFile dient dem Weg zur Unit (Ereignisse).</summary>
    class function Hover(const AText, AFormFile: string; const APosition: TTextPosition; const AIndex: ISymbolIndex;
      const AReadText: TMemberReadText): string; static;
    /// <summary>Sprungziele für Property-Namen, Klassennamen und Aufzählungswerte.</summary>
    class function Targets(const AText: string; const APosition: TTextPosition; const AIndex: ISymbolIndex;
      const AReadText: TMemberReadText): TArray<TSymbolLocation>; static;
    /// <summary>Gespeicherte Werte, die dem default der Property entsprechen.</summary>
    class function RedundantDefaults(const AText: string; const AIndex: ISymbolIndex;
      const AReadText: TMemberReadText): TArray<TRedundantDefault>; static;
  end;

implementation

uses
  System.StrUtils,
  BDLsp.Common.Dfm.Parser,
  BDLsp.Common.Dfm.Navigation,
  BDLsp.Common.Index.Extractor;

const
  MaxDepth = 32;

function Contains(const ARange: TTextRange; const APosition: TTextPosition): Boolean;
begin
  Result := ((APosition.Line > ARange.StartPos.Line) or ((APosition.Line = ARange.StartPos.Line) and
    (APosition.Character >= ARange.StartPos.Character))) and ((APosition.Line < ARange.EndPos.Line) or
    ((APosition.Line = ARange.EndPos.Line) and (APosition.Character <= ARange.EndPos.Character)));
end;

/// <summary>Klasse ohne Unit-Präfix.</summary>
function FindClassSymbol(const AIndex: ISymbolIndex; const AName: string; out ALocation: TSymbolLocation): Boolean;
var
  Location: TSymbolLocation;
  Name: string;
begin
  Name := AName;
  if LastDelimiter('.', Name) > 0 then
    Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  if AIndex <> nil then
    for Location in AIndex.FindSymbols(Name) do
      if (Location.Symbol.Kind = TIndexSymbolKind.ClassType) and (Location.Symbol.Container = '') then
      begin
        ALocation := Location;
        Exit(True);
      end;
  Result := False;
end;

/// <summary>Published-Property AName (auch Font.Style) ab Klasse AClassName.</summary>
function ResolveProperty(const AIndex: ISymbolIndex; const AReadText: TMemberReadText; const AClassName,
  AName: string; out AMember: TPublishedMember): Boolean;
var
  Parts: TArray<string>;
  ClassName: string;
  Index: Integer;
  Member: TPublishedMember;
  Found: Boolean;
begin
  Result := False;
  if AIndex = nil then
    Exit;
  Parts := AName.Split(['.']);
  ClassName := AClassName;
  for Index := 0 to High(Parts) do
  begin
    Found := False;
    for Member in TPublishedMembers.Collect(AIndex, ClassName, AReadText) do
      if SameText(Member.Name, Parts[Index]) then
      begin
        AMember := Member;
        Found := True;
        Break;
      end;
    if not Found then
      Exit;
    ClassName := AMember.TypeName;
  end;
  Result := True;
end;

/// <summary>Klasse der Einträge einer Collection: Typ der Default-Property bzw. von Items.</summary>
function ItemClassOf(const AIndex: ISymbolIndex; const ACollectionType: string): string;
var
  ClassName: string;
  Location, Owner: TSymbolLocation;
  Depth: Integer;
begin
  Result := '';
  ClassName := ACollectionType;
  for Depth := 1 to MaxDepth do
  begin
    for Location in AIndex.FindSymbols('Items') do
      if (Location.Symbol.Kind = TIndexSymbolKind.Property_) and SameText(Location.Symbol.Container, ClassName) and
        (Location.Symbol.TypeName <> '') then
        Exit(Location.Symbol.TypeName);
    if not FindClassSymbol(AIndex, ClassName, Owner) or (Length(Owner.Symbol.Ancestors) = 0) then
      Exit;
    ClassName := Owner.Symbol.Ancestors[0];
  end;
end;

type
  /// <summary>Formulardatei mit Eltern der Objekte.</summary>
  TFormView = class
  private
    FDocument: TDfmDocument;
    FLines: TArray<string>;
    function ParentOf(AParent, AObject: TDfmObject): TDfmObject;
  public
    constructor Create(const AText: string);
    destructor Destroy; override;
    /// <summary>Klasse des Objekts; bei Collection-Einträgen die Item-Klasse der Collection.</summary>
    function ClassOf(AObject: TDfmObject; const AIndex: ISymbolIndex; const AReadText: TMemberReadText): string;
    /// <summary>Wort (Bezeichner) an APosition und sein Bereich.</summary>
    function WordAt(const APosition: TTextPosition; out ARange: TTextRange): string;
    property Document: TDfmDocument read FDocument;
  end;

constructor TFormView.Create(const AText: string);
begin
  inherited Create;
  FDocument := TDfmParser.Parse(AText);
  FLines := StringReplace(AText, #13#10, #10, [rfReplaceAll]).Split([#10]);
end;

destructor TFormView.Destroy;
begin
  FDocument.Free;
  inherited;
end;

function TFormView.ParentOf(AParent, AObject: TDfmObject): TDfmObject;
var
  Child: TDfmObject;
begin
  Result := nil;
  for Child in AParent.Children do
  begin
    if Child = AObject then
      Exit(AParent);
    Result := ParentOf(Child, AObject);
    if Result <> nil then
      Exit;
  end;
end;

function TFormView.ClassOf(AObject: TDfmObject; const AIndex: ISymbolIndex; const AReadText: TMemberReadText): string;
var
  Parent: TDfmObject;
  Item: TDfmProperty;
  Member: TPublishedMember;
  ParentClass: string;
begin
  Result := AObject.TypeName;
  if (AObject.Kind <> TDfmObjectKind.Item) or (FDocument.Root = nil) then
    Exit;
  Result := '';
  Parent := ParentOf(FDocument.Root, AObject);
  if (Parent = nil) or (AIndex = nil) then
    Exit;
  ParentClass := ClassOf(Parent, AIndex, AReadText);
  // Die Collection-Property, in deren Wert (< … >) der Eintrag steht.
  for Item in Parent.Properties do
    if Contains(Item.ValueRange, AObject.Range.StartPos) then
    begin
      if ResolveProperty(AIndex, AReadText, ParentClass, Item.Name, Member) then
        Result := ItemClassOf(AIndex, Member.TypeName);
      Exit;
    end;
end;

function TFormView.WordAt(const APosition: TTextPosition; out ARange: TTextRange): string;
var
  Line: string;
  Start, Stop: Integer;
begin
  Result := '';
  if (APosition.Line < 0) or (APosition.Line > High(FLines)) then
    Exit;
  Line := FLines[APosition.Line];
  Start := APosition.Character;
  while (Start > 0) and CharInSet(Line[Start], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
    Dec(Start);
  Stop := APosition.Character + 1;
  while (Stop <= Length(Line)) and CharInSet(Line[Stop], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
    Inc(Stop);
  Result := Copy(Line, Start + 1, Stop - Start - 1);
  ARange := TTextRange.Create(APosition.Line, Start, APosition.Line, Stop - 1);
end;

/// <summary>Aufzählungswert AName: Ort und Typ.</summary>
function FindEnumMember(const AIndex: ISymbolIndex; const AName: string; out ALocation: TSymbolLocation): Boolean;
var
  Location: TSymbolLocation;
begin
  if (AIndex <> nil) and IsValidIdent(AName) then
    for Location in AIndex.FindSymbols(AName) do
      if Location.Symbol.Kind = TIndexSymbolKind.EnumMember then
      begin
        ALocation := Location;
        Exit(True);
      end;
  Result := False;
end;

function EnumValues(const AIndex: ISymbolIndex; const ALocation: TSymbolLocation): string;
var
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
begin
  Result := '';
  if not AIndex.FindFile(ALocation.FileName, UnitIndex) then
    Exit;
  for Symbol in UnitIndex.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.EnumMember) and SameText(Symbol.Container, ALocation.Symbol.Container) then
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + Symbol.Name;
    end;
end;

function PropertyMarkdown(const AMember: TPublishedMember): string;
var
  Declaration: string;
begin
  Declaration := 'property ' + AMember.Name;
  if AMember.TypeName <> '' then
    Declaration := Declaration + ': ' + AMember.TypeName;
  if AMember.DefaultValue <> '' then
    Declaration := Declaration + ' default ' + AMember.DefaultValue;
  Result := '```pascal' + sLineBreak + Declaration + sLineBreak + '```';
  if AMember.TypeClass <> '' then
    Result := Result + sLineBreak + sLineBreak + 'Deklariert in `' + AMember.TypeClass + '`'
  else
    Result := Result + sLineBreak + sLineBreak + 'Deklariert in `' + AMember.DeclaringClass + '`';
end;

/// <summary>Kopf der Methode AName der Klasse AFormClass in der Unit neben AFormFile.</summary>
function HandlerSignature(const AFormFile, AFormClass, AName: string; const AReadText: TMemberReadText): string;
var
  UnitFile, Text, Line: string;
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
  Lines: TArray<string>;
  Index: Integer;
begin
  Result := '';
  if (AFormFile = '') or not Assigned(AReadText) then
    Exit;
  UnitFile := ChangeFileExt(AFormFile, '.pas');
  if not AReadText(UnitFile, Text) then
    Exit;
  UnitIndex := TIndexExtractor.ExtractText(Text, UnitFile, nil);
  Lines := StringReplace(Text, #13#10, #10, [rfReplaceAll]).Split([#10]);
  for Symbol in UnitIndex.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.Method) and SameText(Symbol.Name, AName) and
      SameText(Symbol.Container, AFormClass) then
    begin
      // Erste Fundstelle ist die Deklaration in der Klasse.
      for Index := Symbol.Range.StartPos.Line to Symbol.Range.EndPos.Line do
      begin
        Line := Trim(Lines[Index]);
        if Result <> '' then
          Result := Result + ' ';
        Result := Result + Line;
        if Pos(';', Line) > 0 then
          Break;
      end;
      Exit('```pascal' + sLineBreak + Result + sLineBreak + '```');
    end;
end;

class function TFormSymbols.Hover(const AText, AFormFile: string; const APosition: TTextPosition;
  const AIndex: ISymbolIndex; const AReadText: TMemberReadText): string;
var
  View: TFormView;
  Current: TDfmObject;
  Item: TDfmProperty;
  Member: TPublishedMember;
  Location: TSymbolLocation;
  ClassName, Word: string;
  WordRange: TTextRange;
begin
  Result := '';
  View := TFormView.Create(AText);
  try
    if View.Document.Root = nil then
      Exit;
    Current := TDfmNavigation.ObjectAt(View.Document, APosition);
    if Current = nil then
      Exit;
    // Klassenname im Kopf des Objekts.
    if (Current.TypeName <> '') and Contains(Current.TypeRange, APosition) then
    begin
      if not FindClassSymbol(AIndex, Current.TypeName, Location) then
        Exit;
      Result := '```pascal' + sLineBreak + Location.Symbol.Name + ' = class';
      if Length(Location.Symbol.Ancestors) > 0 then
        Result := Result + '(' + string.Join(', ', Location.Symbol.Ancestors) + ')';
      Result := Result + sLineBreak + '```' + sLineBreak + sLineBreak + 'Unit `' + Location.UnitName + '`';
      Word := TPublishedMembers.ToMarkdown(TPublishedMembers.Collect(AIndex, Location.Symbol.Name, AReadText));
      if Word <> '' then
        Result := Result + sLineBreak + sLineBreak + Word;
      Exit;
    end;
    ClassName := View.ClassOf(Current, AIndex, AReadText);
    for Item in Current.Properties do
    begin
      if Contains(Item.NameRange, APosition) then
      begin
        if (ClassName <> '') and ResolveProperty(AIndex, AReadText, ClassName, Item.Name, Member) then
          Result := PropertyMarkdown(Member);
        Exit;
      end;
      if not Contains(Item.ValueRange, APosition) then
        Continue;
      if Item.IsEvent then
        Exit(HandlerSignature(AFormFile, View.Document.Root.TypeName, Item.Value, AReadText));
      Word := View.WordAt(APosition, WordRange);
      if FindEnumMember(AIndex, Word, Location) then
        Result := '```pascal' + sLineBreak + Location.Symbol.Name + ': ' + Location.Symbol.Container + sLineBreak +
          '```' + sLineBreak + sLineBreak + 'Werte: ' + EnumValues(AIndex, Location);
      Exit;
    end;
  finally
    View.Free;
  end;
end;

class function TFormSymbols.Targets(const AText: string; const APosition: TTextPosition;
  const AIndex: ISymbolIndex; const AReadText: TMemberReadText): TArray<TSymbolLocation>;
var
  View: TFormView;
  Current: TDfmObject;
  Item: TDfmProperty;
  Member: TPublishedMember;
  Location: TSymbolLocation;
  ClassName, Word, Owner: string;
  WordRange: TTextRange;
begin
  Result := nil;
  if AIndex = nil then
    Exit;
  View := TFormView.Create(AText);
  try
    if View.Document.Root = nil then
      Exit;
    Current := TDfmNavigation.ObjectAt(View.Document, APosition);
    if Current = nil then
      Exit;
    if (Current.TypeName <> '') and Contains(Current.TypeRange, APosition) then
    begin
      if FindClassSymbol(AIndex, Current.TypeName, Location) then
        Result := [Location];
      Exit;
    end;
    ClassName := View.ClassOf(Current, AIndex, AReadText);
    for Item in Current.Properties do
    begin
      if Contains(Item.NameRange, APosition) then
      begin
        if (ClassName = '') or not ResolveProperty(AIndex, AReadText, ClassName, Item.Name, Member) then
          Exit;
        Owner := Member.TypeClass;
        if Owner = '' then
          Owner := Member.DeclaringClass;
        for Location in AIndex.FindSymbols(Member.Name) do
          if (Location.Symbol.Kind = TIndexSymbolKind.Property_) and SameText(Location.Symbol.Container, Owner) then
            Exit([Location]);
        Exit;
      end;
      if Contains(Item.ValueRange, APosition) and not Item.IsEvent then
      begin
        Word := View.WordAt(APosition, WordRange);
        if FindEnumMember(AIndex, Word, Location) then
          Result := [Location];
        Exit;
      end;
    end;
  finally
    View.Free;
  end;
end;

class function TFormSymbols.RedundantDefaults(const AText: string; const AIndex: ISymbolIndex;
  const AReadText: TMemberReadText): TArray<TRedundantDefault>;
var
  View: TFormView;
  Found: TArray<TRedundantDefault>;

  procedure Visit(AObject: TDfmObject);
  var
    Item: TDfmProperty;
    Member: TPublishedMember;
    Entry: TRedundantDefault;
    ClassName: string;
    Child: TDfmObject;
  begin
    ClassName := View.ClassOf(AObject, AIndex, AReadText);
    if ClassName <> '' then
      for Item in AObject.Properties do
        if not Item.IsEvent and ResolveProperty(AIndex, AReadText, ClassName, Item.Name, Member) and
          (Member.DefaultValue <> '') and SameText(Trim(Item.Value), Member.DefaultValue) then
        begin
          Entry.Range := TTextRange.Create(Item.NameRange.StartPos, Item.ValueRange.EndPos);
          Entry.PropertyName := Item.Name;
          Entry.Value := Trim(Item.Value);
          Found := Found + [Entry];
        end;
    for Child in AObject.Children do
      Visit(Child);
  end;

begin
  Found := nil;
  if AIndex = nil then
    Exit(nil);
  View := TFormView.Create(AText);
  try
    if View.Document.Root <> nil then
      Visit(View.Document.Root);
  finally
    View.Free;
  end;
  Result := Found;
end;

end.
