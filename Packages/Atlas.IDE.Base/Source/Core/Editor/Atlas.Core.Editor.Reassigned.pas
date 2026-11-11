unit Atlas.Core.Editor.Reassigned;

// Neu zugewiesene Variablen unterstreichen (#712) ohne VCL und OTA: Argumente
// für atlas.server.reassigned bauen, die Antwort lesen, Stellen je Zeile und
// die Linie (gepunktet, durchgezogen, Welle) als Strecken. Welche Namen
// zählen, rechnet der Server (Atlas.Common.Semantics.Reassigned); Abruf und
// Zeichnen stehen in Atlas.IDE.Editor.Reassigned.
// Antwort: {"symbols": [{"name", "kind", "writes", "routine", "writeLines",
//           "uses": [{"line", "character", "endCharacter", "write"}]}]}
// Gefragt wird nur der sichtbare Teil mit einer Bildschirmhöhe Rand oben und
// unten (TAtlasReassignedRange); der Server rechnet dann nur die Routinen, die
// hineinreichen. Verlässt die Ansicht den Bereich, fragt das Plugin neu.

interface

uses
  System.Types,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Settings.Reassigned;

type
  TAtlasReassignedUse = record
    Line: Integer;
    Character: Integer;
    EndCharacter: Integer;
    Write: Boolean;
    /// <summary>Index des Namens in TAtlasReassignedSet.Symbols.</summary>
    Symbol: Integer;
  end;

  TAtlasReassignedSymbol = record
    Name: string;
    Kind: string;
    Writes: Integer;
    Routine: string;
  end;

  TAtlasReassignedSet = record
  private
    FByLine: TArray<TArray<TAtlasReassignedUse>>;
  public
    Symbols: TArray<TAtlasReassignedSymbol>;
    /// <summary>Die Antwort war lesbar (auch ohne Namen).</summary>
    Valid: Boolean;
    class function FromJson(AValue: TJSONValue): TAtlasReassignedSet; static;
    function HasUses: Boolean;
    /// <summary>Stellen in Zeile ALine (ab 0), nach Zeichen sortiert.</summary>
    function UsesAt(ALine: Integer): TArray<TAtlasReassignedUse>;
  end;

  /// <summary>Strecke von (X1, Y1) nach (X2, Y2).</summary>
  TAtlasUnderlineSegment = record
    X1, Y1, X2, Y2: Integer;
  end;

  /// <summary>Gefragte Zeilen (ab 0, beide eingeschlossen); First &lt; 0: die ganze Datei.</summary>
  TAtlasReassignedRange = record
    First: Integer;
    Last: Integer;
    /// <summary>Die ganze Datei.</summary>
    class function Whole: TAtlasReassignedRange; static;
    /// <summary>Die sichtbaren Zeilen AFirstVisible bis ALastVisible mit einer Bildschirmhöhe Rand oben und unten.
    /// </summary>
    class function Around(AFirstVisible, ALastVisible: Integer): TAtlasReassignedRange; static;
    /// <summary>Liegen die Zeilen AFirstVisible bis ALastVisible ganz im Bereich?</summary>
    function Contains(AFirstVisible, ALastVisible: Integer): Boolean;
  end;

  TAtlasReassigned = class
  public
    /// <summary>Argumente [uri, {targets: [...]}] für die ganze Datei als JSON-Text.</summary>
    class function Arguments(const AUri: string; ATargets: TAtlasReassignedTargets): string; overload; static;
    /// <summary>Argumente [uri, {targets: [...], range: {start, end}}] als JSON-Text; ohne range bei der ganzen
    /// Datei.</summary>
    class function Arguments(const AUri: string; ATargets: TAtlasReassignedTargets;
      const ARange: TAtlasReassignedRange): string; overload; static;
    /// <summary>Strecken der Linie von ALeft bis ARight auf der Grundlinie ABaseline; AUnit ist ein Pixel in der
    /// Bildschirmskalierung (Punkte und Wellen wachsen mit).</summary>
    class function Segments(AStyle: TAtlasReassignedStyle; ALeft, ARight, ABaseline,
      AUnit: Integer): TArray<TAtlasUnderlineSegment>; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.Generics.Defaults;

function Segment(AX1, AY1, AX2, AY2: Integer): TAtlasUnderlineSegment;
begin
  Result.X1 := AX1;
  Result.Y1 := AY1;
  Result.X2 := AX2;
  Result.Y2 := AY2;
end;

function ReadSymbol(const AItem: TJSONObject): TAtlasReassignedSymbol;
begin
  Result.Name := AItem.GetValue<string>('name', '');
  Result.Kind := AItem.GetValue<string>('kind', '');
  Result.Writes := AItem.GetValue<Integer>('writes', 0);
  Result.Routine := AItem.GetValue<string>('routine', '');
end;

/// <summary>Stellen des Symbols ASymbol aus AItem.uses nach AFound; ohne gültige Zeile und Spalten keine.</summary>
procedure AddUses(const AItem: TJSONObject; ASymbol: Integer; AFound: TList<TAtlasReassignedUse>);
var
  mUseItem: TJSONValue;
  mUse: TAtlasReassignedUse;
begin
  if AItem.GetValue('uses') is TJSONArray then
  begin
    for mUseItem in TJSONArray(AItem.GetValue('uses')) do
    begin
      if mUseItem is TJSONObject then
      begin
        mUse.Line := TJSONObject(mUseItem).GetValue<Integer>('line', -1);
        mUse.Character := TJSONObject(mUseItem).GetValue<Integer>('character', 0);
        mUse.EndCharacter := TJSONObject(mUseItem).GetValue<Integer>('endCharacter', 0);
        mUse.Write := TJSONObject(mUseItem).GetValue<Boolean>('write', False);
        mUse.Symbol := ASymbol;
        if (mUse.Line >= 0) and (mUse.EndCharacter > mUse.Character) then
        begin
          AFound.Add(mUse);
        end;
      end;
    end;
  end;
end;

/// <summary>Nach Zeile, Spalte und Symbol.</summary>
function UseComparer: IComparer<TAtlasReassignedUse>;
begin
  Result := TComparer<TAtlasReassignedUse>.Construct(
    function(const ALeft, ARight: TAtlasReassignedUse): Integer
    begin
      Result := ALeft.Line - ARight.Line;
      if Result = 0 then
      begin
        Result := ALeft.Character - ARight.Character;
      end;
      if Result = 0 then
      begin
        Result := ALeft.Symbol - ARight.Symbol;
      end;
    end);
end;

{ TAtlasReassignedSet }

class function TAtlasReassignedSet.FromJson(AValue: TJSONValue): TAtlasReassignedSet;
var
  mItem: TJSONValue;
  mUse: TAtlasReassignedUse;
  mFound: TList<TAtlasReassignedUse>;
begin
  Result := Default(TAtlasReassignedSet);
  if (AValue is TJSONObject) and (TJSONObject(AValue).GetValue('symbols') is TJSONArray) then
  begin
    mFound := TList<TAtlasReassignedUse>.Create;
    try
      for mItem in TJSONArray(TJSONObject(AValue).GetValue('symbols')) do
      begin
        if mItem is TJSONObject then
        begin
          Result.Symbols := Result.Symbols + [ReadSymbol(TJSONObject(mItem))];
          AddUses(TJSONObject(mItem), High(Result.Symbols), mFound);
        end;
      end;
      mFound.Sort(UseComparer);
      for mUse in mFound do
      begin
        if mUse.Line >= Length(Result.FByLine) then
        begin
          SetLength(Result.FByLine, mUse.Line + 1);
        end;
        Result.FByLine[mUse.Line] := Result.FByLine[mUse.Line] + [mUse];
      end;
    finally
      mFound.Free;
    end;
    Result.Valid := True;
  end;
end;

function TAtlasReassignedSet.HasUses: Boolean;
begin
  Result := Length(FByLine) > 0;
end;

function TAtlasReassignedSet.UsesAt(ALine: Integer): TArray<TAtlasReassignedUse>;
begin
  Result := nil;
  if (ALine >= 0) and (ALine < Length(FByLine)) then
  begin
    Result := FByLine[ALine];
  end;
end;

{ TAtlasReassignedRange }

class function TAtlasReassignedRange.Whole: TAtlasReassignedRange;
begin
  Result.First := -1;
  Result.Last := -1;
end;

class function TAtlasReassignedRange.Around(AFirstVisible, ALastVisible: Integer): TAtlasReassignedRange;
var
  mHeight: Integer;
begin
  mHeight := Max(1, ALastVisible - AFirstVisible + 1);
  Result.First := Max(0, AFirstVisible - mHeight);
  Result.Last := Max(Result.First, ALastVisible + mHeight);
end;

function TAtlasReassignedRange.Contains(AFirstVisible, ALastVisible: Integer): Boolean;
begin
  Result := (First < 0) or ((AFirstVisible >= First) and (ALastVisible <= Last));
end;

{ TAtlasReassigned }

class function TAtlasReassigned.Arguments(const AUri: string; ATargets: TAtlasReassignedTargets): string;
begin
  Result := Arguments(AUri, ATargets, TAtlasReassignedRange.Whole);
end;

class function TAtlasReassigned.Arguments(const AUri: string; ATargets: TAtlasReassignedTargets;
  const ARange: TAtlasReassignedRange): string;
var
  mValues, mTargets: TJSONArray;
  mOptions, mRange: TJSONObject;
  mTarget: TAtlasReassignedTarget;
begin
  mValues := TJSONArray.Create;
  try
    mValues.Add(AUri);
    mOptions := TJSONObject.Create;
    mTargets := TJSONArray.Create;
    for mTarget := Low(TAtlasReassignedTarget) to High(TAtlasReassignedTarget) do
    begin
      if mTarget in ATargets then
      begin
        mTargets.Add(TAtlasReassignedNames.TargetName(mTarget));
      end;
    end;
    mOptions.AddPair('targets', mTargets);
    if ARange.First >= 0 then
    begin
      mRange := TJSONObject.Create;
      mRange.AddPair('start', TJSONNumber.Create(ARange.First));
      mRange.AddPair('end', TJSONNumber.Create(ARange.Last));
      mOptions.AddPair('range', mRange);
    end;
    mValues.AddElement(mOptions);
    Result := mValues.ToJSON;
  finally
    mValues.Free;
  end;
end;

class function TAtlasReassigned.Segments(AStyle: TAtlasReassignedStyle; ALeft, ARight, ABaseline,
  AUnit: Integer): TArray<TAtlasUnderlineSegment>;
var
  mStep, X, mNext: Integer;
  mUp: Boolean;
begin
  Result := nil;
  if ARight <= ALeft then
  begin
    Exit;
  end;
  mStep := Max(1, AUnit);
  case AStyle of
    TAtlasReassignedStyle.Solid:
      Result := [Segment(ALeft, ABaseline, ARight, ABaseline)];
    TAtlasReassignedStyle.Wavy:
      begin
        // Je 2 Einheiten auf und ab wie die Wellenlinie der Probleme, nur flacher.
        X := ALeft;
        mUp := False;
        while X < ARight do
        begin
          mNext := Min(ARight, X + 2 * mStep);
          if mUp then
          begin
            Result := Result + [Segment(X, ABaseline - mStep, mNext, ABaseline)];
          end
          else
          begin
            Result := Result + [Segment(X, ABaseline, mNext, ABaseline - mStep)];
          end;
          mUp := not mUp;
          X := mNext;
        end;
      end;
  else
    begin
      // Punkte: eine Einheit lang, eine Einheit Abstand.
      X := ALeft;
      while X < ARight do
      begin
        Result := Result + [Segment(X, ABaseline, Min(ARight, X + mStep), ABaseline)];
        Inc(X, 2 * mStep);
      end;
    end;
  end;
end;

end.
