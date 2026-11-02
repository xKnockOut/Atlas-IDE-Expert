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
      Continue;
    if not ASlots[Index].Separator then
    begin
      ButtonBefore := True;
      Continue;
    end;
    Next := Index + 1;
    while (Next <= High(ASlots)) and (not AShown[Next] or ASlots[Next].Separator) do
      Inc(Next);
    if not ButtonBefore or (Next > High(ASlots)) then
      AShown[Index] := False
    else
      // Bis zum nächsten Knopf kein weiterer Trennstrich.
      ButtonBefore := False;
  end;
end;

function WidthOf(const ASlots: TArray<TAtlasToolbarSlot>; const AShown: TArray<Boolean>): Integer;
var
  Index: Integer;
begin
  Result := 0;
  for Index := 0 to High(ASlots) do
    if AShown[Index] then
      Inc(Result, ASlots[Index].Width);
end;

class function TAtlasToolbarLayout.FullWidth(const ASlots: TArray<TAtlasToolbarSlot>): Integer;
var
  Shown: TArray<Boolean>;
  Index: Integer;
begin
  SetLength(Shown, Length(ASlots));
  for Index := 0 to High(Shown) do
    Shown[Index] := True;
  HideLoneSeparators(ASlots, Shown);
  Result := WidthOf(ASlots, Shown);
end;

class function TAtlasToolbarLayout.Fit(const ASlots: TArray<TAtlasToolbarSlot>; AAvailable,
  AMoreWidth: Integer): TAtlasToolbarFit;
var
  Index, Used, Limit: Integer;
  Full, InMenu: Boolean;
  Menu: TArray<Boolean>;
begin
  Result := Default(TAtlasToolbarFit);
  SetLength(Result.Visible, Length(ASlots));
  for Index := 0 to High(ASlots) do
    Result.Visible[Index] := True;
  HideLoneSeparators(ASlots, Result.Visible);
  Result.Used := WidthOf(ASlots, Result.Visible);
  if Result.Used <= AAvailable then
    Exit;
  Result.More := True;
  Limit := AAvailable - AMoreWidth;
  // Angeheftete zählen vorab: Sie bleiben in jedem Fall.
  Used := 0;
  for Index := 0 to High(ASlots) do
    if ASlots[Index].Pinned then
      Inc(Used, ASlots[Index].Width);
  Full := False;
  SetLength(Menu, Length(ASlots));
  for Index := 0 to High(ASlots) do
  begin
    Result.Visible[Index] := ASlots[Index].Pinned;
    Menu[Index] := False;
    if ASlots[Index].Pinned then
      Continue;
    if not Full and (Used + ASlots[Index].Width <= Limit) then
    begin
      Result.Visible[Index] := True;
      Inc(Used, ASlots[Index].Width);
    end
    else
    begin
      Full := True;
      Menu[Index] := True;
    end;
  end;
  HideLoneSeparators(ASlots, Result.Visible);
  HideLoneSeparators(ASlots, Menu);
  Result.Used := WidthOf(ASlots, Result.Visible);
  Result.Overflow := nil;
  InMenu := False;
  for Index := 0 to High(ASlots) do
    if Menu[Index] then
    begin
      Result.Overflow := Result.Overflow + [Index];
      InMenu := True;
    end;
  // Nur Trennstriche im Menü wären kein Grund für ».
  Result.More := InMenu;
end;

end.
