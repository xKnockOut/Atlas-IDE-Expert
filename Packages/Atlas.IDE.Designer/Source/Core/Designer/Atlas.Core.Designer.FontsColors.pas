unit Atlas.Core.Designer.FontsColors;

// Schriften und Farben eines Formulars (#741), ohne VCL und Windows.
// - Eingabe: je Komponente ihre Schrift (Name, Größe in Punkt, Stil als
//   Bitmaske, Farbe als Text wie „clRed“ oder „$00102030“), ParentFont,
//   Color, ParentColor und der Name des Parents ('' beim Formular).
// - Schriften: je Kombination eine Zeile mit den Komponenten, die sie selbst
//   setzen, und denen, die sie erben; die Schrift des Formulars ist markiert.
// - Farben: je Wert von Color und Font.Color (selbst gesetzt) eine Zeile;
//   Werte aus der Ignorierliste fehlen.
// - Ausreißer: Zeilen mit höchstens zwei eigenen Komponenten.
// - Ersetzen: nur die gewählten Teile (Name, Größe, Stil, Farbe). Gleicht der
//   neue Wert dem des Parents (nach allen Änderungen, über mehrere Ebenen),
//   wird mit ARestoreParent wieder ParentFont bzw. ParentColor gesetzt.
// - Höhe: Font.Height = -Size * PixelsPerInch / 72, gerundet.

interface

type
  TAtlasFontPart = (Name, Size, Style, Color);
  TAtlasFontParts = set of TAtlasFontPart;

  TAtlasFontKey = record
    Name: string;
    Size: Integer;
    Style: Integer;
    Color: string;
    class function Create(const AName: string; ASize, AStyle: Integer; const AColor: string): TAtlasFontKey; static;
    function Same(const AOther: TAtlasFontKey): Boolean;
    /// <summary>Gleich in den Teilen AParts?</summary>
    function SameIn(const AOther: TAtlasFontKey; AParts: TAtlasFontParts): Boolean;
  end;

  TAtlasFontUse = record
    Component: string;
    ParentName: string;
    Font: TAtlasFontKey;
    ParentFont: Boolean;
    Color: string;
    ParentColor: Boolean;
    /// <summary>Komponente hat eine Eigenschaft Color (sonst zählt nur die Schrift).</summary>
    HasColor: Boolean;
  end;

  TAtlasFontRow = record
    Font: TAtlasFontKey;
    Own: TArray<string>;
    Inherits: TArray<string>;
    IsFormFont: Boolean;
    Outlier: Boolean;
  end;

  TAtlasColorRow = record
    Color: string;
    Components: TArray<string>;
    Outlier: Boolean;
  end;

  /// <summary>Ersetzungsregel: Schriften, die in Match From gleichen, bekommen die Teile Parts von Target.</summary>
  TAtlasFontRule = record
    From: TAtlasFontKey;
    Target: TAtlasFontKey;
    Match: TAtlasFontParts;
    Parts: TAtlasFontParts;
    class function Create(const AFrom, ATarget: TAtlasFontKey; AMatch, AParts: TAtlasFontParts): TAtlasFontRule; static;
  end;

  TAtlasFontChange = record
    Component: string;
    Font: TAtlasFontKey;
    /// <summary>Statt der Schrift wieder ParentFont = True setzen.</summary>
    ToParent: Boolean;
  end;

  TAtlasColorChange = record
    Component: string;
    Color: string;
    ToParent: Boolean;
  end;

  TAtlasFontsColors = class
  public const
    cOutlierMax = 2;
    cDefaultIgnore = 'clWindow, clBtnFace, clWindowText, clDefault';
  public
    class function FontRows(const AUses: TArray<TAtlasFontUse>; const AFormName: string): TArray<TAtlasFontRow>; static;
    class function ColorRows(const AUses: TArray<TAtlasFontUse>; const AIgnore: string): TArray<TAtlasColorRow>; static;
    /// <summary>AFont mit den Teilen AParts aus ATarget.</summary>
    class function Merge(const AFont, ATarget: TAtlasFontKey; AParts: TAtlasFontParts): TAtlasFontKey; static;
    /// <summary>Schriften nach ARule ersetzen; AOnly leer = alle.</summary>
    class function FontPlan(const AUses: TArray<TAtlasFontUse>; const ARule: TAtlasFontRule; ARestoreParent: Boolean;
      const AOnly: TArray<string>): TArray<TAtlasFontChange>; static;
    /// <summary>Color = AFrom durch ATarget ersetzen; AOnly leer = alle.</summary>
    class function ColorPlan(const AUses: TArray<TAtlasFontUse>; const AFrom, ATarget: string;
      ARestoreParent: Boolean; const AOnly: TArray<string>): TArray<TAtlasColorChange>; static;
    /// <summary>Font.Height zur Größe in Punkt bei APixelsPerInch.</summary>
    class function HeightOf(ASize, APixelsPerInch: Integer): Integer; static;
    /// <summary>Zeilentext einer Schrift, z. B. „Segoe UI 9 fett“; AStyleNames in Bitreihenfolge.</summary>
    class function FontText(const AFont: TAtlasFontKey; const AStyleNames: array of string): string; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasFontKey }

class function TAtlasFontKey.Create(const AName: string; ASize, AStyle: Integer; const AColor: string): TAtlasFontKey;
begin
  Result.Name := AName;
  Result.Size := ASize;
  Result.Style := AStyle;
  Result.Color := AColor;
end;

function TAtlasFontKey.Same(const AOther: TAtlasFontKey): Boolean;
begin
  Result := SameIn(AOther, [TAtlasFontPart.Name, TAtlasFontPart.Size, TAtlasFontPart.Style, TAtlasFontPart.Color]);
end;

function TAtlasFontKey.SameIn(const AOther: TAtlasFontKey; AParts: TAtlasFontParts): Boolean;
begin
  Result := not ((TAtlasFontPart.Name in AParts) and not SameText(Name, AOther.Name)) and
    not ((TAtlasFontPart.Size in AParts) and (Size <> AOther.Size)) and
    not ((TAtlasFontPart.Style in AParts) and (Style <> AOther.Style)) and
    not ((TAtlasFontPart.Color in AParts) and not SameText(Color, AOther.Color));
end;

{ Hilfen }

function IndexOfUse(const AUses: TArray<TAtlasFontUse>; const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AUses) do
  begin
    if SameText(AUses[mIndex].Component, AName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function Listed(const ANames: TArray<string>; const AName: string): Boolean;
var
  mName: string;
begin
  for mName in ANames do
  begin
    if SameText(Trim(mName), AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Wirksame Schrift von AIndex: eigene oder die des nächsten Parents, der sie setzt.</summary>
function Effective(const AUses: TArray<TAtlasFontUse>; AIndex: Integer): TAtlasFontKey;
var
  mIndex, mParent, mGuard: Integer;
begin
  mIndex := AIndex;
  mGuard := Length(AUses);
  while AUses[mIndex].ParentFont and (mGuard > 0) do
  begin
    mParent := IndexOfUse(AUses, AUses[mIndex].ParentName);
    if mParent < 0 then
    begin
      Break;
    end;
    mIndex := mParent;
    Dec(mGuard);
  end;
  Result := AUses[mIndex].Font;
end;

function EffectiveColor(const AUses: TArray<TAtlasFontUse>; AIndex: Integer): string;
var
  mIndex, mParent, mGuard: Integer;
begin
  mIndex := AIndex;
  mGuard := Length(AUses);
  while AUses[mIndex].ParentColor and (mGuard > 0) do
  begin
    mParent := IndexOfUse(AUses, AUses[mIndex].ParentName);
    if mParent < 0 then
    begin
      Break;
    end;
    mIndex := mParent;
    Dec(mGuard);
  end;
  Result := AUses[mIndex].Color;
end;

function OwnsFont(const AUse: TAtlasFontUse): Boolean;
begin
  Result := not AUse.ParentFont or (AUse.ParentName = '');
end;

function OwnsColor(const AUse: TAtlasFontUse): Boolean;
begin
  Result := AUse.HasColor and (not AUse.ParentColor or (AUse.ParentName = ''));
end;

{ TAtlasFontRule }

class function TAtlasFontRule.Create(const AFrom, ATarget: TAtlasFontKey;
  AMatch, AParts: TAtlasFontParts): TAtlasFontRule;
begin
  Result.From := AFrom;
  Result.Target := ATarget;
  Result.Match := AMatch;
  Result.Parts := AParts;
end;

{ TAtlasFontsColors }

class function TAtlasFontsColors.FontRows(const AUses: TArray<TAtlasFontUse>;
  const AFormName: string): TArray<TAtlasFontRow>;
var
  mIndex, mRow: Integer;
  mFont, mForm: TAtlasFontKey;
  mFound: Boolean;
begin
  Result := nil;
  mForm := Default(TAtlasFontKey);
  mFound := IndexOfUse(AUses, AFormName) >= 0;
  if mFound then
  begin
    mForm := AUses[IndexOfUse(AUses, AFormName)].Font;
  end;
  for mIndex := 0 to High(AUses) do
  begin
    mFont := Effective(AUses, mIndex);
    mRow := 0;
    while (mRow <= High(Result)) and not Result[mRow].Font.Same(mFont) do
    begin
      Inc(mRow);
    end;
    if mRow > High(Result) then
    begin
      SetLength(Result, mRow + 1);
      Result[mRow].Font := mFont;
      Result[mRow].IsFormFont := mFound and mForm.Same(mFont);
    end;
    if OwnsFont(AUses[mIndex]) then
    begin
      Result[mRow].Own := Result[mRow].Own + [AUses[mIndex].Component];
    end
    else
    begin
      Result[mRow].Inherits := Result[mRow].Inherits + [AUses[mIndex].Component];
    end;
  end;
  for mRow := 0 to High(Result) do
  begin
    Result[mRow].Outlier := not Result[mRow].IsFormFont and (Length(Result[mRow].Own) > 0) and
      (Length(Result[mRow].Own) <= cOutlierMax);
  end;
end;

class function TAtlasFontsColors.ColorRows(const AUses: TArray<TAtlasFontUse>;
  const AIgnore: string): TArray<TAtlasColorRow>;
var
  mIgnore: TArray<string>;
  mUse: TAtlasFontUse;
  mRows: TArray<TAtlasColorRow>;

  procedure Count(const AColor, AComponent: string);
  var
    mRow: Integer;
  begin
    if (AColor = '') or Listed(mIgnore, AColor) then
    begin
      Exit;
    end;
    mRow := 0;
    while (mRow <= High(mRows)) and not SameText(mRows[mRow].Color, AColor) do
    begin
      Inc(mRow);
    end;
    if mRow > High(mRows) then
    begin
      SetLength(mRows, mRow + 1);
      mRows[mRow].Color := AColor;
    end;
    if not Listed(mRows[mRow].Components, AComponent) then
    begin
      mRows[mRow].Components := mRows[mRow].Components + [AComponent];
    end;
  end;

var
  mRow: Integer;
begin
  mRows := nil;
  mIgnore := AIgnore.Split([',', ';']);
  for mUse in AUses do
  begin
    if OwnsColor(mUse) then
    begin
      Count(mUse.Color, mUse.Component);
    end;
    if OwnsFont(mUse) then
    begin
      Count(mUse.Font.Color, mUse.Component);
    end;
  end;
  for mRow := 0 to High(mRows) do
  begin
    mRows[mRow].Outlier := Length(mRows[mRow].Components) <= cOutlierMax;
  end;
  Result := mRows;
end;

class function TAtlasFontsColors.Merge(const AFont, ATarget: TAtlasFontKey; AParts: TAtlasFontParts): TAtlasFontKey;
begin
  Result := AFont;
  if TAtlasFontPart.Name in AParts then
  begin
    Result.Name := ATarget.Name;
  end;
  if TAtlasFontPart.Size in AParts then
  begin
    Result.Size := ATarget.Size;
  end;
  if TAtlasFontPart.Style in AParts then
  begin
    Result.Style := ATarget.Style;
  end;
  if TAtlasFontPart.Color in AParts then
  begin
    Result.Color := ATarget.Color;
  end;
end;

class function TAtlasFontsColors.FontPlan(const AUses: TArray<TAtlasFontUse>; const ARule: TAtlasFontRule;
  ARestoreParent: Boolean; const AOnly: TArray<string>): TArray<TAtlasFontChange>;
var
  mAfter: TArray<TAtlasFontUse>;
  mIndex, mParent: Integer;
  mChange: TAtlasFontChange;
begin
  Result := nil;
  mAfter := Copy(AUses);
  for mIndex := 0 to High(mAfter) do
  begin
    if OwnsFont(mAfter[mIndex]) and mAfter[mIndex].Font.SameIn(ARule.From, ARule.Match) and
      ((Length(AOnly) = 0) or Listed(AOnly, mAfter[mIndex].Component)) then
    begin
      mAfter[mIndex].Font := Merge(mAfter[mIndex].Font, ARule.Target, ARule.Parts);
      mChange.Component := mAfter[mIndex].Component;
      mChange.Font := mAfter[mIndex].Font;
      mChange.ToParent := False;
      Result := Result + [mChange];
    end;
  end;
  if not ARestoreParent then
  begin
    Exit;
  end;
  // Erst alle neuen Werte, dann die Parents vergleichen: so zählt auch ein geänderter Parent.
  for mIndex := 0 to High(Result) do
  begin
    mParent := IndexOfUse(mAfter, mAfter[IndexOfUse(mAfter, Result[mIndex].Component)].ParentName);
    Result[mIndex].ToParent := (mParent >= 0) and Effective(mAfter, mParent).Same(Result[mIndex].Font);
  end;
end;

class function TAtlasFontsColors.ColorPlan(const AUses: TArray<TAtlasFontUse>; const AFrom, ATarget: string;
  ARestoreParent: Boolean; const AOnly: TArray<string>): TArray<TAtlasColorChange>;
var
  mAfter: TArray<TAtlasFontUse>;
  mIndex, mParent: Integer;
  mChange: TAtlasColorChange;
begin
  Result := nil;
  mAfter := Copy(AUses);
  for mIndex := 0 to High(mAfter) do
  begin
    if OwnsColor(mAfter[mIndex]) and SameText(mAfter[mIndex].Color, AFrom) and
      ((Length(AOnly) = 0) or Listed(AOnly, mAfter[mIndex].Component)) then
    begin
      mAfter[mIndex].Color := ATarget;
      mChange.Component := mAfter[mIndex].Component;
      mChange.Color := ATarget;
      mChange.ToParent := False;
      Result := Result + [mChange];
    end;
  end;
  for mIndex := 0 to High(Result) do
  begin
    mParent := IndexOfUse(mAfter, mAfter[IndexOfUse(mAfter, Result[mIndex].Component)].ParentName);
    Result[mIndex].ToParent := ARestoreParent and (mParent >= 0) and
      SameText(EffectiveColor(mAfter, mParent), ATarget);
  end;
end;

class function TAtlasFontsColors.HeightOf(ASize, APixelsPerInch: Integer): Integer;
begin
  Result := -((ASize * APixelsPerInch + 36) div 72);
end;

class function TAtlasFontsColors.FontText(const AFont: TAtlasFontKey; const AStyleNames: array of string): string;
var
  mBit: Integer;
begin
  Result := AFont.Name + ' ' + IntToStr(AFont.Size);
  for mBit := 0 to High(AStyleNames) do
  begin
    if AFont.Style and (1 shl mBit) <> 0 then
    begin
      Result := Result + ' ' + AStyleNames[mBit];
    end;
  end;
end;

end.
