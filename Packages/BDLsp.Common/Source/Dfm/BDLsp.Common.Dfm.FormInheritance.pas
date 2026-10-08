unit BDLsp.Common.Dfm.FormInheritance;

// Geerbte Formulare mit dem Vorfahr vergleichen (#115). Eine Formulardatei
// mit "inherited"-Objekten wird mit der Kette ihrer Vorfahr-Formulare
// verglichen (TForm2 = class(TBasis) → Unit von TBasis → deren .dfm, auch
// über mehrere Stufen; bei "inline"-Frames ist die Frame-Klasse der Vorfahr).
// Liefert zu einer Property
// - den geerbten Wert und die Stufe, auf der er gesetzt ist,
// - die Werte aller Stufen,
// - bei Collections (<item>-Listen) den Hinweis, dass die Liste ersetzt wird,
// - den Edit "auf geerbten Wert zurücksetzen", der genau die Property-Zeilen
//   entfernt.
// Ist ein Vorfahr nicht auflösbar, gibt es keinen Hinweis statt eines
// falschen Werts.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Dfm.Contract;

type
  /// <summary>Formulardatei des Vorfahren von AClassName; False, wenn keine auflösbar ist.</summary>
  TFormClassResolver = reference to function(const AClassName: string; out AFormFile, AFormText: string): Boolean;
  /// <summary>Vorfahr-Klasse der Formularklasse in AFormFile; '' ohne.</summary>
  TFormAncestorOf = reference to function(const AFormFile, AFormClass: string): string;

  TFormLevel = record
    FormClass: string;
    FileName: string;
    Document: TDfmDocument;
  end;

  /// <summary>Wert einer Property auf einer Stufe der Vererbung.</summary>
  TInheritedValue = record
    FormClass: string;
    FileName: string;
    Value: string;
  end;

  TFormInheritance = class
  public const
    MaxLevels = 16;
  private
    FLevels: TList<TFormLevel>;
    function FindProperty(const APosition: TTextPosition; out AObject: TDfmObject;
      out AProperty: TDfmProperty): Boolean;
  public
    /// <summary>Liest AFormText und alle Vorfahr-Formulare über AAncestorOf und AResolve.</summary>
    constructor Create(const AFormFile, AFormText: string; const AAncestorOf: TFormAncestorOf;
      const AResolve: TFormClassResolver);
    destructor Destroy; override;
    /// <summary>Werte von AProperty in den Vorfahren, nächster Vorfahr zuerst.</summary>
    function InheritedValues(AObject: TDfmObject; const APropertyName: string): TArray<TInheritedValue>;
    /// <summary>Markdown für den Hover über einer Property; '' ohne Vorfahrwert.</summary>
    function HoverAt(const APosition: TTextPosition): string;
    /// <summary>"Auf geerbten Wert zurücksetzen" für die Property an APosition.</summary>
    function ResetAt(const APosition: TTextPosition; out AEdit: TRuleEdit; out ATitle: string): Boolean;
    /// <summary>Formulare der Kette: [0] das eigene, dann die Vorfahren.</summary>
    function Levels: TArray<TFormLevel>;
    /// <summary>Resolver über den Symbolindex: Klasse → Unit → .dfm/.fmx daneben.</summary>
    /// <summary>Vorfahr laut Unit neben der Formulardatei (Formularmodell, #267).</summary>
    class function UnitAncestorOf(const AReadText: TFunc<string, string>): TFormAncestorOf; static;
    class function IndexResolver(const AIndex: ISymbolIndex; const AReadText: TFunc<string, string>): TFormClassResolver; static;
  end;

implementation

uses
  System.StrUtils,
  BDLsp.Common.Dfm.FormFiles,
  BDLsp.Common.Dfm.Parser,
  BDLsp.Common.Dfm.FormModel;

function FindByName(AObject: TDfmObject; const AName: string): TDfmObject;
var
  Child: TDfmObject;
begin
  if SameText(AObject.Name, AName) then
    Exit(AObject);
  for Child in AObject.Children do
  begin
    Result := FindByName(Child, AName);
    if Result <> nil then
      Exit;
  end;
  Result := nil;
end;

function FindAtLine(AObject: TDfmObject; ALine: Integer; out AProperty: TDfmProperty): TDfmObject;
var
  Child: TDfmObject;
  Item: TDfmProperty;
begin
  Result := nil;
  if (ALine < AObject.Range.StartPos.Line) or (ALine > AObject.Range.EndPos.Line) then
    Exit;
  for Child in AObject.Children do
  begin
    Result := FindAtLine(Child, ALine, AProperty);
    if Result <> nil then
      Exit;
  end;
  for Item in AObject.Properties do
    if (ALine >= Item.NameRange.StartPos.Line) and (ALine <= Item.ValueRange.EndPos.Line) then
    begin
      AProperty := Item;
      Exit(AObject);
    end;
end;

function ValueOf(AObject: TDfmObject; const AName: string; out AValue: string): Boolean;
var
  Item: TDfmProperty;
begin
  for Item in AObject.Properties do
    if SameText(Item.Name, AName) then
    begin
      AValue := Item.Value;
      Exit(True);
    end;
  Result := False;
end;

function IsCollection(const AValue: string): Boolean;
begin
  Result := StartsStr('<', TrimLeft(AValue));
end;

{ TFormInheritance }

constructor TFormInheritance.Create(const AFormFile, AFormText: string; const AAncestorOf: TFormAncestorOf;
  const AResolve: TFormClassResolver);
var
  Level: TFormLevel;
  Ancestor, FileName, Text: string;
  Seen: string;
begin
  inherited Create;
  FLevels := TList<TFormLevel>.Create;
  Level.FileName := AFormFile;
  Level.Document := TDfmParser.Parse(AFormText);
  Level.FormClass := '';
  if Level.Document.Root <> nil then
    Level.FormClass := Level.Document.Root.TypeName;
  FLevels.Add(Level);
  Seen := ';' + LowerCase(Level.FormClass) + ';';
  while (FLevels.Count < MaxLevels) and Assigned(AAncestorOf) and Assigned(AResolve) do
  begin
    Level := FLevels.Last;
    Ancestor := AAncestorOf(Level.FileName, Level.FormClass);
    if (Ancestor = '') or (Pos(';' + LowerCase(Ancestor) + ';', Seen) > 0) or
      not AResolve(Ancestor, FileName, Text) or TFormModel.IsBinary(Text) then
      Break;
    Seen := Seen + LowerCase(Ancestor) + ';';
    Level.FileName := FileName;
    Level.FormClass := Ancestor;
    Level.Document := TDfmParser.Parse(Text);
    FLevels.Add(Level);
  end;
end;

destructor TFormInheritance.Destroy;
var
  Level: TFormLevel;
begin
  if FLevels <> nil then
    for Level in FLevels do
      Level.Document.Free;
  FLevels.Free;
  inherited;
end;

function TFormInheritance.Levels: TArray<TFormLevel>;
begin
  Result := FLevels.ToArray;
end;

function TFormInheritance.InheritedValues(AObject: TDfmObject; const APropertyName: string): TArray<TInheritedValue>;
var
  Index: Integer;
  Target: TDfmObject;
  Entry: TInheritedValue;
begin
  Result := nil;
  for Index := 1 to FLevels.Count - 1 do
  begin
    if FLevels[Index].Document.Root = nil then
      Continue;
    // Das Formular selbst ist die Wurzel; Komponenten werden über den Namen zugeordnet.
    if AObject = FLevels[0].Document.Root then
      Target := FLevels[Index].Document.Root
    else
      Target := FindByName(FLevels[Index].Document.Root, AObject.Name);
    if (Target <> nil) and ValueOf(Target, APropertyName, Entry.Value) then
    begin
      Entry.FormClass := FLevels[Index].FormClass;
      Entry.FileName := FLevels[Index].FileName;
      Result := Result + [Entry];
    end;
  end;
end;

function TFormInheritance.FindProperty(const APosition: TTextPosition; out AObject: TDfmObject;
  out AProperty: TDfmProperty): Boolean;
begin
  AObject := nil;
  if (FLevels.Count < 2) or (FLevels[0].Document.Root = nil) then
    Exit(False);
  AObject := FindAtLine(FLevels[0].Document.Root, APosition.Line, AProperty);
  // Nur geerbte Objekte und das Formular selbst haben Werte im Vorfahren.
  Result := (AObject <> nil) and ((AObject = FLevels[0].Document.Root) or
    (AObject.Kind in [TDfmObjectKind.Inherited_, TDfmObjectKind.Inline_]));
end;

function OneLine(const AValue: string): string;
begin
  Result := Trim(StringReplace(StringReplace(AValue, #13#10, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
  if Length(Result) > 80 then
    Result := Copy(Result, 1, 77) + '...';
end;

function TFormInheritance.HoverAt(const APosition: TTextPosition): string;
var
  Obj: TDfmObject;
  Item: TDfmProperty;
  Values: TArray<TInheritedValue>;
  Entry: TInheritedValue;
begin
  Result := '';
  if not FindProperty(APosition, Obj, Item) then
    Exit;
  Values := InheritedValues(Obj, Item.Name);
  if Values = nil then
    Exit;
  if IsCollection(Item.Value) then
    Result := Format('**%s** ersetzt die geerbte Liste aus %s.', [Item.Name, Values[0].FormClass])
  else
    Result := Format('**%s** überschreibt den geerbten Wert `%s` aus %s.',
      [Item.Name, OneLine(Values[0].Value), Values[0].FormClass]);
  Result := Result + #10#10'Stufen:'#10 + Format('- %s: `%s` (hier)', [FLevels[0].FormClass, OneLine(Item.Value)]);
  for Entry in Values do
    Result := Result + #10 + Format('- %s: `%s` (%s)', [Entry.FormClass, OneLine(Entry.Value),
      ExtractFileName(Entry.FileName)]);
end;

function TFormInheritance.ResetAt(const APosition: TTextPosition; out AEdit: TRuleEdit; out ATitle: string): Boolean;
var
  Obj: TDfmObject;
  Item: TDfmProperty;
  Values: TArray<TInheritedValue>;
begin
  Result := False;
  if not FindProperty(APosition, Obj, Item) then
    Exit;
  Values := InheritedValues(Obj, Item.Name);
  if Values = nil then
    Exit;
  // Ganze Zeilen der Property, auch mehrzeilige Werte.
  AEdit := TRuleEdit.Create(TTextRange.Create(Item.NameRange.StartPos.Line, 0, Item.ValueRange.EndPos.Line + 1, 0), '');
  ATitle := Format('%s auf geerbten Wert zurücksetzen (%s)', [Item.Name, OneLine(Values[0].Value)]);
  Result := True;
end;

class function TFormInheritance.UnitAncestorOf(const AReadText: TFunc<string, string>): TFormAncestorOf;
begin
  Result :=
    function(const AFormFile, AFormClass: string): string
    var
      UnitText: string;
      Model: TFormModel;
    begin
      Result := '';
      UnitText := AReadText(TFormFiles.UnitFile(AFormFile));
      if UnitText = '' then
        Exit;
      Model := TFormModel.Create(AReadText(AFormFile), UnitText, TFormFiles.UnitFile(AFormFile));
      try
        Result := Model.Ancestor;
      finally
        Model.Free;
      end;
    end;
end;

class function TFormInheritance.IndexResolver(const AIndex: ISymbolIndex;
  const AReadText: TFunc<string, string>): TFormClassResolver;
begin
  Result :=
    function(const AClassName: string; out AFormFile, AFormText: string): Boolean
    var
      Location: TSymbolLocation;
      Extension: string;
    begin
      Result := False;
      if AIndex = nil then
        Exit;
      for Location in AIndex.FindSymbols(AClassName) do
        if (Location.Symbol.Kind = TIndexSymbolKind.ClassType) and (Location.Symbol.Container = '') then
          for Extension in TArray<string>.Create('.dfm', '.fmx') do
          begin
            AFormFile := ChangeFileExt(Location.FileName, Extension);
            AFormText := AReadText(AFormFile);
            if AFormText <> '' then
              Exit(True);
          end;
    end;
end;

end.
