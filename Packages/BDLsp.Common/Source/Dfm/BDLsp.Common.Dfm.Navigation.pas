unit BDLsp.Common.Dfm.Navigation;

// Sprünge aus einer Formulardatei in die Unit daneben (#44):
//   - Ereignis (OnClick = Button1Click): zur Implementierung der Methode,
//     sonst zur Deklaration in der Formularklasse
//   - Komponentenname (object Button1: TButton): zum Feld der Formularklasse
//   - Name des Formulars: zur Klassendeklaration
// Die Unit heißt wie die Formulardatei mit .pas. Die Gegenrichtung (Methode
// → Ereignis in der DFM) liefert die Referenzsuche.

interface

uses
  System.SysUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Dfm.Contract;

type
  TDfmTarget = record
    FileName: string;
    Range: TTextRange;
    SelectionRange: TTextRange;
  end;

  TDfmReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  TDfmNavigation = class
  public
    /// <summary>Innerstes Objekt an APosition; nil außerhalb.</summary>
    class function ObjectAt(ADocument: TDfmDocument; const APosition: TTextPosition): TDfmObject; static;
    /// <summary>Sprungziele für APosition in der Formulardatei ADfmFileName.</summary>
    class function Targets(const ADfmText, ADfmFileName: string; const APosition: TTextPosition;
      const AReadText: TDfmReadText): TArray<TDfmTarget>; static;
  end;

implementation

uses
  BDLsp.Common.Dfm.FormFiles,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Index.Extractor,
  BDLsp.Common.Dfm.Parser;

function Contains(const ARange: TTextRange; const APosition: TTextPosition): Boolean;
begin
  Result := ((APosition.Line > ARange.StartPos.Line) or
    ((APosition.Line = ARange.StartPos.Line) and (APosition.Character >= ARange.StartPos.Character))) and
    ((APosition.Line < ARange.EndPos.Line) or
    ((APosition.Line = ARange.EndPos.Line) and (APosition.Character <= ARange.EndPos.Character)));
end;

function Target(const AFileName: string; const ASymbol: TIndexSymbol): TDfmTarget;
begin
  Result.FileName := AFileName;
  Result.Range := ASymbol.Range;
  Result.SelectionRange := ASymbol.SelectionRange;
end;

{ TDfmNavigation }

class function TDfmNavigation.ObjectAt(ADocument: TDfmDocument; const APosition: TTextPosition): TDfmObject;
var
  Current: TDfmObject;
  Child: TDfmObject;
  Found: Boolean;
begin
  Result := nil;
  Current := ADocument.Root;
  while (Current <> nil) and Contains(Current.Range, APosition) do
  begin
    Result := Current;
    Found := False;
    for Child in Current.Children do
      if Contains(Child.Range, APosition) then
      begin
        Current := Child;
        Found := True;
        Break;
      end;
    if not Found then
      Break;
  end;
end;

class function TDfmNavigation.Targets(const ADfmText, ADfmFileName: string; const APosition: TTextPosition;
  const AReadText: TDfmReadText): TArray<TDfmTarget>;
var
  Document: TDfmDocument;
  Current: TDfmObject;
  Item: TDfmProperty;
  Wanted, FormClass, UnitFile, UnitText: string;
  WantedKinds: set of TIndexSymbolKind;
  UnitIndex: TUnitIndex;
  Symbol, Best: TIndexSymbol;
  HasBest: Boolean;
begin
  Result := nil;
  Document := TDfmParser.Parse(ADfmText);
  try
    if Document.Root = nil then
      Exit;
    FormClass := Document.Root.TypeName;
    Current := ObjectAt(Document, APosition);
    if Current = nil then
      Exit;
    Wanted := '';
    WantedKinds := [];
    for Item in Current.Properties do
      if Item.IsEvent and Contains(Item.ValueRange, APosition) then
      begin
        Wanted := Item.Value;
        WantedKinds := [TIndexSymbolKind.Method];
        Break;
      end;
    if (Wanted = '') and (Current.Name <> '') and Contains(Current.NameRange, APosition) then
    begin
      Wanted := Current.Name;
      if Current = Document.Root then
        WantedKinds := [TIndexSymbolKind.ClassType]
      else
        WantedKinds := [TIndexSymbolKind.Field];
    end;
  finally
    Document.Free;
  end;
  if (Wanted = '') or not Assigned(AReadText) then
    Exit;
  UnitFile := TFormFiles.UnitFile(ADfmFileName);
  if not AReadText(UnitFile, UnitText) then
    Exit;
  UnitIndex := TIndexExtractor.ExtractText(UnitText, UnitFile, nil);
  HasBest := False;
  Best := Default(TIndexSymbol);
  for Symbol in UnitIndex.Symbols do
  begin
    if not (Symbol.Kind in WantedKinds) then
      Continue;
    if WantedKinds = [TIndexSymbolKind.ClassType] then
    begin
      // Formularklasse: Name im DFM ist der Komponentenname, gesucht ist die Klasse.
      if not SameText(Symbol.Name, FormClass) then
        Continue;
    end
    else if not SameText(Symbol.Name, Wanted) or not SameText(Symbol.Container, FormClass) then
      Continue;
    // Bei Methoden gewinnt die Implementierung (die letzte Fundstelle).
    if not HasBest or (Symbol.Range.StartPos.Line > Best.Range.StartPos.Line) then
    begin
      Best := Symbol;
      HasBest := True;
    end;
  end;
  if HasBest then
    Result := [Target(UnitFile, Best)];
end;

end.
