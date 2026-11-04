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
  Index, Next: Integer;
  ButtonBefore: Boolean;
begin
  ButtonBefore := False;
  for Index := 0 to High(ASlots) do
  begin
    if not AShown[Index] then
    begin
      Continue;
    end;
    if not ASlots[Index].Separator then
    begin
      ButtonBefore := True;
      Continue;
    end;
    Next := Index + 1;
    while (Next <= High(ASlots)) and (not AShown[Next] or ASlots[Next].Separator) do
    begin
      Inc(Next);
    end;
    if not ButtonBefore or (Next > High(ASlots)) then
    begin
      AShown[Index] := False;
    end
    else
    begin
      // Bis zum nächsten Knopf kein weiterer Trennstrich.
      ButtonBefore := False;
    end;
  end;
end;

function WidthOf(const ASlots: TArray<TAtlasToolbarSlot>; const AShown: TArray<Boolean>): Integer;
var
  Index: Integer;
begin
  Result := 0;
  for Index := 0 to High(ASlots) do
  begin
    if AShown[Index] then
    begin
      Inc(Result, ASlots[Index].Width);
    end;
  end;
end;

/// <summary>Breite der angehefteten Plätze: Sie bleiben in jedem Fall.</summary>
function PinnedWidth(const ASlots: TArray<TAtlasToolbarSlot>): Integer;
var
  Index: Integer;
begin
  Result := 0;
  for Index := 0 to High(ASlots) do
  begin
    if ASlots[Index].Pinned then
    begin
      Inc(Result, ASlots[Index].Width);
    end;
  end;
end;

/// <summary>Verteilt die Plätze der Reihe nach auf Leiste und Menü, bis ALimit erreicht ist.</summary>
procedure Distribute(const ASlots: TArray<TAtlasToolbarSlot>; ALimit: Integer; out AVisible, AMenu: TArray<Boolean>);
var
  Index, Used: Integer;
  Full: Boolean;
begin
  Used := PinnedWidth(ASlots);
  Full := False;
  SetLength(AVisible, Length(ASlots));
  SetLength(AMenu, Length(ASlots));
  for Index := 0 to High(ASlots) do
  begin
    AVisible[Index] := ASlots[Index].Pinned;
    AMenu[Index] := False;
    if ASlots[Index].Pinned then
    begin
      Continue;
    end;
    if not Full and (Used + ASlots[Index].Width <= ALimit) then
    begin
      AVisible[Index] := True;
      Inc(Used, ASlots[Index].Width);
    end
    else
    begin
      Full := True;
      AMenu[Index] := True;
    end;
  end;
end;

function ShownIndices(const AShown: TArray<Boolean>): TArray<Integer>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to High(AShown) do
  begin
    if AShown[Index] then
    begin
      Result := Result + [Index];
    end;
  end;
end;
class function TAtlasToolbarLayout.FullWidth(const ASlots: TArray<TAtlasToolbarSlot>): Integer;
var
  Shown: TArray<Boolean>;
  Index: Integer;
begin
  SetLength(Shown, Length(ASlots));
  for Index := 0 to High(Shown) do
  begin
    Shown[Index] := True;
  end;
  HideLoneSeparators(ASlots, Shown);
  Result := WidthOf(ASlots, Shown);
end;

class function TAtlasToolbarLayout.Fit(const ASlots: TArray<TAtlasToolbarSlot>; AAvailable,
  AMoreWidth: Integer): TAtlasToolbarFit;
var
  Index: Integer;
  Menu: TArray<Boolean>;
begin
  Result := Default(TAtlasToolbarFit);
  SetLength(Result.Visible, Length(ASlots));
  for Index := 0 to High(ASlots) do
  begin
    Result.Visible[Index] := True;
  end;
  HideLoneSeparators(ASlots, Result.Visible);
  Result.Used := WidthOf(ASlots, Result.Visible);
  if Result.Used > AAvailable then
  begin
    Distribute(ASlots, AAvailable - AMoreWidth, Result.Visible, Menu);
    HideLoneSeparators(ASlots, Result.Visible);
    HideLoneSeparators(ASlots, Menu);
    Result.Used := WidthOf(ASlots, Result.Visible);
    Result.Overflow := ShownIndices(Menu);
    // Nur Trennstriche im Menü wären kein Grund für ».
    Result.More := Length(Result.Overflow) > 0;
  end;
end;

end.
