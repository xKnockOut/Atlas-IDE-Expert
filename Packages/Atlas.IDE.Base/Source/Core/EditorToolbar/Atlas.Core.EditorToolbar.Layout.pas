unit Atlas.Core.EditorToolbar.Layout;

// Atlas-Editorleiste (#1101), Überlauf-Layout ohne VCL und OTA: Die Leiste
// hat eine feste Höhe; reicht die Breite nicht, wandern die hinteren Knöpfe in
// das Menü ». Fit verteilt die Einträge:
// - Passen alle, braucht es kein ».
// - Sonst bleibt Platz für » frei. Von vorn bleibt sichtbar, was passt; ab
//   dem ersten Knopf, der nicht passt, kommt alles Weitere ins Menü (die
//   Reihenfolge bleibt, kein kleinerer Knopf rückt nach). Angeheftete Einträge
//   (Abschnittssymbole und Rücksprung) bleiben immer sichtbar.
// - Trennstriche stehen nur zwischen zwei sichtbaren Knöpfen; im Menü nur
//   zwischen zwei Einträgen, nie am Anfang, am Ende oder doppelt.

interface

uses
  System.SysUtils;

type
  TAtlasToolbarSlot = record
    Width: Integer;
    Separator: Boolean;
    /// <summary>Wandert nie in den Überlauf.</summary>
    Pinned: Boolean;
    class function Create(AWidth: Integer; ASeparator, APinned: Boolean): TAtlasToolbarSlot; static;
  end;

  TAtlasToolbarFit = record
    /// <summary>Je Eintrag: in der Leiste sichtbar.</summary>
    Visible: TArray<Boolean>;
    /// <summary>Einträge des Menüs » in Reihenfolge, Trennstriche nur zwischen Einträgen.</summary>
    Overflow: TArray<Integer>;
    /// <summary>Braucht es den Knopf »?</summary>
    More: Boolean;
    /// <summary>Breite der sichtbaren Einträge (ohne »).</summary>
    Used: Integer;
  end;

  TAtlasToolbarLayout = class
  public
    /// <summary>Verteilt ASlots auf AAvailable Pixel; AMoreWidth ist die Breite von ».</summary>
    class function Fit(const ASlots: TArray<TAtlasToolbarSlot>; AAvailable, AMoreWidth: Integer): TAtlasToolbarFit;
      static;
    /// <summary>Breite aller Einträge ohne Überlauf (Trennstriche nur zwischen Knöpfen).</summary>
    class function FullWidth(const ASlots: TArray<TAtlasToolbarSlot>): Integer; static;
  end;

implementation

{ TAtlasToolbarSlot }

class function TAtlasToolbarSlot.Create(AWidth: Integer; ASeparator, APinned: Boolean): TAtlasToolbarSlot;
begin
  Result.Width := AWidth;
  Result.Separator := ASeparator;
  Result.Pinned := APinned;
end;

{ TAtlasToolbarLayout }

/// <summary>Trennstriche nur zwischen zwei gezeigten Knöpfen.</summary>
procedure HideLoneSeparators(const ASlots: TArray<TAtlasToolbarSlot>; var AShown: TArray<Boolean>);
var
  mIndex, mNext: Integer;
  mButtonBefore: Boolean;
begin
  mButtonBefore := False;
  for mIndex := 0 to High(ASlots) do
  begin
    if not AShown[mIndex] then
    begin
      Continue;
    end;
    if not ASlots[mIndex].Separator then
    begin
      mButtonBefore := True;
      Continue;
    end;
    mNext := mIndex + 1;
    while (mNext <= High(ASlots)) and (not AShown[mNext] or ASlots[mNext].Separator) do
    begin
      Inc(mNext);
    end;
    if not mButtonBefore or (mNext > High(ASlots)) then
    begin
      AShown[mIndex] := False;
    end
    else
    begin
      // Bis zum nächsten Knopf kein weiterer Trennstrich.
      mButtonBefore := False;
    end;
  end;
end;

function WidthOf(const ASlots: TArray<TAtlasToolbarSlot>; const AShown: TArray<Boolean>): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := 0 to High(ASlots) do
  begin
    if AShown[mIndex] then
    begin
      Inc(Result, ASlots[mIndex].Width);
    end;
  end;
end;

/// <summary>Breite der angehefteten Plätze: Sie bleiben in jedem Fall.</summary>
function PinnedWidth(const ASlots: TArray<TAtlasToolbarSlot>): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := 0 to High(ASlots) do
  begin
    if ASlots[mIndex].Pinned then
    begin
      Inc(Result, ASlots[mIndex].Width);
    end;
  end;
end;

/// <summary>Verteilt die Plätze der Reihe nach auf Leiste und Menü, bis ALimit erreicht ist.</summary>
procedure Distribute(const ASlots: TArray<TAtlasToolbarSlot>; ALimit: Integer; out AVisible, AMenu: TArray<Boolean>);
var
  mIndex, mUsed: Integer;
  mFull: Boolean;
begin
  mUsed := PinnedWidth(ASlots);
  mFull := False;
  SetLength(AVisible, Length(ASlots));
  SetLength(AMenu, Length(ASlots));
  for mIndex := 0 to High(ASlots) do
  begin
    AVisible[mIndex] := ASlots[mIndex].Pinned;
    AMenu[mIndex] := False;
    if ASlots[mIndex].Pinned then
    begin
      Continue;
    end;
    if not mFull and (mUsed + ASlots[mIndex].Width <= ALimit) then
    begin
      AVisible[mIndex] := True;
      Inc(mUsed, ASlots[mIndex].Width);
    end
    else
    begin
      mFull := True;
      AMenu[mIndex] := True;
    end;
  end;
end;

function ShownIndices(const AShown: TArray<Boolean>): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(AShown) do
  begin
    if AShown[mIndex] then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;
class function TAtlasToolbarLayout.FullWidth(const ASlots: TArray<TAtlasToolbarSlot>): Integer;
var
  mShown: TArray<Boolean>;
  mIndex: Integer;
begin
  SetLength(mShown, Length(ASlots));
  for mIndex := 0 to High(mShown) do
  begin
    mShown[mIndex] := True;
  end;
  HideLoneSeparators(ASlots, mShown);
  Result := WidthOf(ASlots, mShown);
end;

class function TAtlasToolbarLayout.Fit(const ASlots: TArray<TAtlasToolbarSlot>; AAvailable,
  AMoreWidth: Integer): TAtlasToolbarFit;
var
  mIndex: Integer;
  mMenu: TArray<Boolean>;
begin
  Result := Default(TAtlasToolbarFit);
  SetLength(Result.Visible, Length(ASlots));
  for mIndex := 0 to High(ASlots) do
  begin
    Result.Visible[mIndex] := True;
  end;
  HideLoneSeparators(ASlots, Result.Visible);
  Result.Used := WidthOf(ASlots, Result.Visible);
  if Result.Used > AAvailable then
  begin
    Distribute(ASlots, AAvailable - AMoreWidth, Result.Visible, mMenu);
    HideLoneSeparators(ASlots, Result.Visible);
    HideLoneSeparators(ASlots, mMenu);
    Result.Used := WidthOf(ASlots, Result.Visible);
    Result.Overflow := ShownIndices(mMenu);
    // Nur Trennstriche im Menü wären kein Grund für ».
    Result.More := Length(Result.Overflow) > 0;
  end;
end;

end.
