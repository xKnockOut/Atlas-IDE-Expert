unit Atlas.Common.Dfm.Navigation;

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
  Atlas.Common.Documents.Contract,
  Atlas.Common.Dfm.Contract;

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
  Atlas.Common.Dfm.FormFiles,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Dfm.Parser;

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
    begin
      if Contains(Child.Range, APosition) then
      begin
        Current := Child;
        Found := True;
        Break;
      end;
    end;
    if not Found then
    begin
      Break;
    end;
  end;
end;

type
  /// <summary>Gesuchtes Symbol zur Stelle im Formular.</summary>
  TDfmWanted = record
    Name: string;
    FormClass: string;
    Kinds: set of TIndexSymbolKind;
  end;

/// <summary>Gesuchtes Symbol unter APosition: Ereignismethode im Wert oder Komponente bzw. Formular im Namen.
/// False ohne.</summary>
function WantedAt(const ADfmText: string; const APosition: TTextPosition; out AWanted: TDfmWanted): Boolean;
var
  mDocument: TDfmDocument;
  mCurrent: TDfmObject;
  mItem: TDfmProperty;
begin
  AWanted := Default(TDfmWanted);
  mDocument := TDfmParser.Parse(ADfmText);
  try
    mCurrent := nil;
    if mDocument.Root <> nil then
    begin
      AWanted.FormClass := mDocument.Root.TypeName;
      mCurrent := TDfmNavigation.ObjectAt(mDocument, APosition);
    end;
    if mCurrent = nil then
    begin
      Exit(False);
    end;
    for mItem in mCurrent.Properties do
    begin
      if mItem.IsEvent and Contains(mItem.ValueRange, APosition) then
      begin
        AWanted.Name := mItem.Value;
        AWanted.Kinds := [TIndexSymbolKind.Method];
        Break;
      end;
    end;
    if (AWanted.Name = '') and (mCurrent.Name <> '') and Contains(mCurrent.NameRange, APosition) then
    begin
      AWanted.Name := mCurrent.Name;
      AWanted.Kinds := [TIndexSymbolKind.Field];
      if mCurrent = mDocument.Root then
      begin
        AWanted.Kinds := [TIndexSymbolKind.ClassType];
      end;
    end;
    Result := AWanted.Name <> '';
  finally
    mDocument.Free;
  end;
end;

/// <summary>ASymbol ist das gesuchte: Formularklasse bzw. Feld oder Methode der Formularklasse.</summary>
function IsWanted(const ASymbol: TIndexSymbol; const AWanted: TDfmWanted): Boolean;
begin
  Result := ASymbol.Kind in AWanted.Kinds;
  if Result and (AWanted.Kinds = [TIndexSymbolKind.ClassType]) then
  begin
    // Formularklasse: Name im DFM ist der Komponentenname, gesucht ist die Klasse.
    Result := SameText(ASymbol.Name, AWanted.FormClass);
  end
  else if Result then
  begin
    Result := SameText(ASymbol.Name, AWanted.Name) and SameText(ASymbol.Container, AWanted.FormClass);
  end;
end;

/// <summary>Gesuchtes Symbol in AUnitIndex; bei Methoden gewinnt die Implementierung (die letzte Fundstelle).
/// </summary>
function BestSymbol(const AUnitIndex: TUnitIndex; const AWanted: TDfmWanted; out ABest: TIndexSymbol): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  Result := False;
  ABest := Default(TIndexSymbol);
  for mSymbol in AUnitIndex.Symbols do
  begin
    if IsWanted(mSymbol, AWanted) and (not Result or (mSymbol.Range.StartPos.Line > ABest.Range.StartPos.Line)) then
    begin
      ABest := mSymbol;
      Result := True;
    end;
  end;
end;

class function TDfmNavigation.Targets(const ADfmText, ADfmFileName: string; const APosition: TTextPosition;
  const AReadText: TDfmReadText): TArray<TDfmTarget>;
var
  mWanted: TDfmWanted;
  mUnitFile, mUnitText: string;
  mBest: TIndexSymbol;
begin
  Result := nil;
  if not WantedAt(ADfmText, APosition, mWanted) or not Assigned(AReadText) then
  begin
    Exit;
  end;
  mUnitFile := TFormFiles.UnitFile(ADfmFileName);
  if AReadText(mUnitFile, mUnitText) and
    BestSymbol(TIndexExtractor.ExtractText(mUnitText, mUnitFile, nil), mWanted, mBest) then
  begin
    Result := [Target(mUnitFile, mBest)];
  end;
end;

end.
