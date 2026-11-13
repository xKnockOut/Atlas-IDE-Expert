unit Atlas.Core.Editor.MethodAnchor;

// Verankerung einer Zeile an ihrer Methode, ohne VCL und Open Tools API;
// gemeinsam für benannte Lesezeichen (#622), Haltepunkt-Sätze (#586) und
// Haltepunkte, die mit dem Code wandern (#841). Ein Anker merkt sich zur
// Zeile (TAtlasLineAnchor: Inhalt und Nachbarzeilen) die Methode, in deren
// Rumpf sie steht (voller Name und Parametertypen für Überladungen), und den
// Abstand zur Kopfzeile. Find sucht zuerst die Methode, dann die Zeile in
// ihrem Rumpf (TAtlasLineAnchors.Locate im Bereich des Rumpfs, ab Kopfzeile
// plus Abstand); Rang bei mehreren Rümpfen gleichen Namens: gleiche
// Parametertypen vor anderen, unveränderte Zeile vor geänderter, dann die
// nächste zur bisherigen Zeile. Außerhalb einer Methode gilt die ganze Datei.
// Zehn Zeilen über der Methode eingefügt: Die Methode beginnt später, die
// Zeile steht wieder im selben Abstand (Moved).
// JSON (Lesezeichen, Haltepunkt-Sätze): method, signature, offset (nur mit
// Methode), line (ab 1), lineText, before, after.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Editor.LineAnchor,
  Atlas.Core.Editor.MethodToggle;

type
  TAtlasMethodAnchor = record
    /// <summary>Voller Name der Methode, z. B. TKunde.Laden; leer außerhalb einer Methode.</summary>
    Method: string;
    /// <summary>Parametertypen der Methode (klein, mit Komma) für Überladungen.</summary>
    Signature: string;
    /// <summary>Abstand der Zeile zur Kopfzeile der Methode.</summary>
    Offset: Integer;
    Anchor: TAtlasLineAnchor;
    /// <summary>Zeile, 0-basiert.</summary>
    function Line: Integer;
    function SameAs(const AOther: TAtlasMethodAnchor): Boolean;
  end;

  /// <summary>Zeilen und Methoden eines Textes, einmal für alle Anker einer Datei.</summary>
  TAtlasMethodAnchorText = record
    Lines: TArray<string>;
    Places: TArray<TAtlasMethodPlace>;
    class function Create(const AText: string): TAtlasMethodAnchorText; static;
  end;

  TAtlasMethodAnchors = class
  public
    /// <summary>Anker der Zeile ALine (0-basiert).</summary>
    class function Capture(const AText: TAtlasMethodAnchorText; ALine: Integer): TAtlasMethodAnchor; overload;
      static;
    class function Capture(const AText: string; ALine: Integer): TAtlasMethodAnchor; overload; static;
    /// <summary>Zeile von AAnchor in AText suchen (Ablauf oben). ALine ist die gefundene Zeile, bei Orphaned die
    /// bisherige.</summary>
    class function Find(const AText: TAtlasMethodAnchorText; const AAnchor: TAtlasMethodAnchor;
      out ALine: Integer): TAtlasLineMatch; overload; static;
    class function Find(const AText: string; const AAnchor: TAtlasMethodAnchor; out ALine: Integer): TAtlasLineMatch;
      overload; static;
    /// <summary>Felder des Ankers an AObject anhängen.</summary>
    class procedure AddTo(AObject: TJSONObject; const AAnchor: TAtlasMethodAnchor); static;
    /// <summary>Anker aus den Feldern von AObject; fehlende Felder leer, line ab 1 (Vorgabe 1).</summary>
    class function ReadFrom(AObject: TJSONObject): TAtlasMethodAnchor; static;
  end;

implementation

uses
  System.Math,
  Atlas.Text.Json;

{ TAtlasMethodAnchor }

function TAtlasMethodAnchor.Line: Integer;
begin
  Result := Anchor.Line;
end;

function TAtlasMethodAnchor.SameAs(const AOther: TAtlasMethodAnchor): Boolean;
begin
  Result := Anchor.SameAs(AOther.Anchor) and (Method = AOther.Method) and (Signature = AOther.Signature) and
    (Offset = AOther.Offset);
end;

{ TAtlasMethodAnchorText }

class function TAtlasMethodAnchorText.Create(const AText: string): TAtlasMethodAnchorText;
begin
  Result.Lines := TAtlasLineAnchors.Lines(AText);
  Result.Places := TAtlasMethodToggle.Places(AText);
end;

{ TAtlasMethodAnchors }

class function TAtlasMethodAnchors.Capture(const AText: TAtlasMethodAnchorText; ALine: Integer): TAtlasMethodAnchor;
var
  mPlace: TAtlasMethodPlace;
begin
  Result := Default(TAtlasMethodAnchor);
  Result.Anchor := TAtlasLineAnchors.Capture(AText.Lines, ALine);
  if TAtlasMethodToggle.BodyAt(AText.Places, ALine, mPlace) then
  begin
    Result.Method := mPlace.Name;
    Result.Signature := mPlace.Signature;
    Result.Offset := ALine - mPlace.FirstLine;
  end;
end;

class function TAtlasMethodAnchors.Capture(const AText: string; ALine: Integer): TAtlasMethodAnchor;
begin
  Result := Capture(TAtlasMethodAnchorText.Create(AText), ALine);
end;

/// <summary>Zeilentext von AAnchor im Rumpf APlace suchen; ARank wie oben (kleiner ist besser). False, wenn der
/// Rumpf nicht passt.</summary>
function MatchInPlace(const AText: TAtlasMethodAnchorText; const AAnchor: TAtlasMethodAnchor;
  const APlace: TAtlasMethodPlace; out AMatch: TAtlasLineMatch; out ALine, ARank: Integer): Boolean;
var
  mAnchor: TAtlasLineAnchor;
begin
  ALine := -1;
  ARank := 0;
  AMatch := TAtlasLineMatch.Orphaned;
  Result := APlace.IsBody and SameText(APlace.Name, AAnchor.Method);
  if not Result then
  begin
    Exit;
  end;
  mAnchor := AAnchor.Anchor;
  mAnchor.Line := Min(APlace.FirstLine + Max(0, AAnchor.Offset), APlace.LastLine);
  AMatch := TAtlasLineAnchors.Locate(AText.Lines, mAnchor, APlace.FirstLine, APlace.LastLine, ALine);
  Result := AMatch <> TAtlasLineMatch.Orphaned;
  if not SameText(APlace.Signature, AAnchor.Signature) then
  begin
    Inc(ARank, 2);
  end;
  if AMatch = TAtlasLineMatch.Changed then
  begin
    Inc(ARank);
  end;
end;

class function TAtlasMethodAnchors.Find(const AText: TAtlasMethodAnchorText; const AAnchor: TAtlasMethodAnchor;
  out ALine: Integer): TAtlasLineMatch;
var
  mPlace: TAtlasMethodPlace;
  mMatch, mBestMatch: TAtlasLineMatch;
  mLine, mRank, mBestRank, mBestLine: Integer;
begin
  ALine := AAnchor.Anchor.Line;
  // Außerhalb einer Methode: Zeilentext in der ganzen Datei.
  if AAnchor.Method = '' then
  begin
    Exit(TAtlasLineAnchors.Locate(AText.Lines, AAnchor.Anchor, ALine));
  end;
  Result := TAtlasLineMatch.Orphaned;
  mBestRank := MaxInt;
  mBestLine := -1;
  mBestMatch := TAtlasLineMatch.Orphaned;
  for mPlace in AText.Places do
  begin
    if MatchInPlace(AText, AAnchor, mPlace, mMatch, mLine, mRank) and ((mRank < mBestRank) or
      ((mRank = mBestRank) and (Abs(mLine - AAnchor.Anchor.Line) < Abs(mBestLine - AAnchor.Anchor.Line)))) then
    begin
      mBestRank := mRank;
      mBestLine := mLine;
      mBestMatch := mMatch;
    end;
  end;
  if mBestLine < 0 then
  begin
    Exit;
  end;
  ALine := mBestLine;
  if mBestMatch = TAtlasLineMatch.Changed then
  begin
    Result := TAtlasLineMatch.Changed;
  end
  else if mBestLine = AAnchor.Anchor.Line then
  begin
    Result := TAtlasLineMatch.Same;
  end
  else
  begin
    Result := TAtlasLineMatch.Moved;
  end;
end;

class function TAtlasMethodAnchors.Find(const AText: string; const AAnchor: TAtlasMethodAnchor;
  out ALine: Integer): TAtlasLineMatch;
begin
  Result := Find(TAtlasMethodAnchorText.Create(AText), AAnchor, ALine);
end;

function TextsJson(const ATexts: TArray<string>): TJSONArray;
var
  mText: string;
begin
  Result := TJSONArray.Create;
  for mText in ATexts do
  begin
    Result.Add(mText);
  end;
end;

function TextsOf(AObject: TJSONObject; const AName: string): TArray<string>;
var
  mValue: TJSONValue;
  mList: TJSONArray;
  mIndex: Integer;
begin
  Result := nil;
  mValue := AObject.GetValue(AName);
  if not (mValue is TJSONArray) then
  begin
    Exit;
  end;
  mList := TJSONArray(mValue);
  for mIndex := 0 to mList.Count - 1 do
  begin
    if (mList.Items[mIndex] is TJSONString) and (Length(Result) < TAtlasLineAnchors.cContextLines) then
    begin
      Result := Result + [TJSONString(mList.Items[mIndex]).Value];
    end;
  end;
end;

class procedure TAtlasMethodAnchors.AddTo(AObject: TJSONObject; const AAnchor: TAtlasMethodAnchor);
begin
  if AAnchor.Method <> '' then
  begin
    AObject.AddPair('method', AAnchor.Method);
    AObject.AddPair('signature', AAnchor.Signature);
    AObject.AddPair('offset', TJSONNumber.Create(AAnchor.Offset));
  end;
  AObject.AddPair('line', TJSONNumber.Create(AAnchor.Anchor.Line + 1));
  AObject.AddPair('lineText', AAnchor.Anchor.Text);
  AObject.AddPair('before', TextsJson(AAnchor.Anchor.Before));
  AObject.AddPair('after', TextsJson(AAnchor.Anchor.After));
end;

class function TAtlasMethodAnchors.ReadFrom(AObject: TJSONObject): TAtlasMethodAnchor;
begin
  Result := Default(TAtlasMethodAnchor);
  if AObject = nil then
  begin
    Exit;
  end;
  Result.Method := TJsonRead.Text(AObject, 'method');
  Result.Signature := TJsonRead.Text(AObject, 'signature');
  Result.Offset := Max(0, TJsonRead.IntOr(AObject, 'offset', 0));
  Result.Anchor.Line := Max(0, TJsonRead.IntOr(AObject, 'line', 1) - 1);
  Result.Anchor.Text := TJsonRead.Text(AObject, 'lineText');
  Result.Anchor.Before := TextsOf(AObject, 'before');
  Result.Anchor.After := TextsOf(AObject, 'after');
end;

end.
