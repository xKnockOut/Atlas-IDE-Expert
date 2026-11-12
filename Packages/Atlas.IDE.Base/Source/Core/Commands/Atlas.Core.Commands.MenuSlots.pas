unit Atlas.Core.Commands.MenuSlots;

// Verteilung der Einträge der Module auf die festen Plätze im Untermenü
// „Atlas“ des Editor-Kontextmenüs (#1455). Die IDE kennt nur die einmal
// registrierte Aktionsliste; Module kommen und gehen. Deshalb hält das
// Kontextmenü einen Vorrat ausgeblendeter Aktionen: Plätze direkt im
// Untermenü (Top) und eine feste Zahl von Untermenüs mit je fester Zahl von
// Plätzen (Groups). Einträge mit Section landen im Untermenü dieses Namens
// (Reihenfolge des ersten Auftretens), die übrigen direkt im Untermenü Atlas.
// Ein flaches Menü mit allen Einträgen war höher als der Bildschirm und oben
// abgeschnitten.
// Trennlinien (Id „-“) erscheinen nur zwischen sichtbaren Befehlen derselben
// Liste; ein Untermenü ohne sichtbaren Befehl bleibt aus.
// MenuName bildet Namen für Einträge, die die IDE als Komponentennamen
// übernimmt (Kontextmenü der Projektverwaltung: IOTALocalMenu.Name wird zu
// TMenuItem.Name). Ein Punkt darin ließ jeden Rechtsklick in der
// Projektverwaltung im Menüaufbau der IDE scheitern.
// Ohne VCL und Open Tools API.

interface

type
  /// <summary>Eintrag eines Moduls: Id „-“ ist eine Trennlinie; Section '' = direkt im Untermenü Atlas.</summary>
  TAtlasSlotItem = record
    Id: string;
    Section: string;
    Visible: Boolean;
  end;

  /// <summary>Eine Liste fester Plätze: je Platz der Index in den Einträgen (-1 = frei) und ob er sichtbar ist.
  /// Caption ist der Name des Untermenüs ('' = unbenutzt bzw. oberste Ebene); Shown: mindestens ein Befehl sichtbar.
  /// </summary>
  TAtlasSlotList = record
    Caption: string;
    Items: TArray<Integer>;
    Visible: TArray<Boolean>;
    Shown: Boolean;
  end;

  /// <summary>Belegung aller Plätze; Missing zählt Einträge ohne freien Platz.</summary>
  TAtlasSlotLayout = record
    Top: TAtlasSlotList;
    Groups: TArray<TAtlasSlotList>;
    Missing: Integer;
  end;

  TAtlasMenuSlots = record
  private
    class function NewList(ACount: Integer): TAtlasSlotList; static;
    class function GroupOf(var ALayout: TAtlasSlotLayout; const ASection: string): Integer; static;
    class procedure Place(var AList: TAtlasSlotList; AItem: Integer; var AMissing: Integer); static;
    class procedure Decide(var AList: TAtlasSlotList; const AItems: TArray<TAtlasSlotItem>); static;
  public
    /// <summary>Verteilt AItems auf ATopCount Plätze und AGroupCount Untermenüs mit je AGroupSize Plätzen.</summary>
    class function Layout(const AItems: TArray<TAtlasSlotItem>; ATopCount, AGroupCount,
      AGroupSize: Integer): TAtlasSlotLayout; static;
    /// <summary>Gültiger Komponentenname aus APrefix und ANumber: nur Buchstaben A–Z, Ziffern und '_', beginnt mit
    /// einem Buchstaben ('Atlas' vorn, wenn APrefix keinen liefert).</summary>
    class function MenuName(const APrefix: string; ANumber: Integer): string; static;
  end;

implementation

uses
  System.SysUtils;

class function TAtlasMenuSlots.NewList(ACount: Integer): TAtlasSlotList;
var
  mIndex: Integer;
begin
  Result := Default(TAtlasSlotList);
  SetLength(Result.Items, ACount);
  SetLength(Result.Visible, ACount);
  for mIndex := 0 to ACount - 1 do
  begin
    Result.Items[mIndex] := -1;
    Result.Visible[mIndex] := False;
  end;
end;

class function TAtlasMenuSlots.GroupOf(var ALayout: TAtlasSlotLayout; const ASection: string): Integer;
var
  mGroup: Integer;
begin
  Result := -1;
  for mGroup := 0 to High(ALayout.Groups) do
  begin
    if ALayout.Groups[mGroup].Caption = '' then
    begin
      ALayout.Groups[mGroup].Caption := ASection;
    end;
    if ALayout.Groups[mGroup].Caption = ASection then
    begin
      Exit(mGroup);
    end;
  end;
end;

class procedure TAtlasMenuSlots.Place(var AList: TAtlasSlotList; AItem: Integer; var AMissing: Integer);
var
  mSlot: Integer;
begin
  for mSlot := 0 to High(AList.Items) do
  begin
    if AList.Items[mSlot] < 0 then
    begin
      AList.Items[mSlot] := AItem;
      Exit;
    end;
  end;
  Inc(AMissing);
end;

class procedure TAtlasMenuSlots.Decide(var AList: TAtlasSlotList; const AItems: TArray<TAtlasSlotItem>);
var
  mSlot, mItem, mPending: Integer;
begin
  // Trennlinie erst zeigen, wenn nach ihr ein sichtbarer Befehl folgt und vor ihr einer stand; von mehreren
  // aufeinanderfolgenden nur die letzte.
  mPending := -1;
  for mSlot := 0 to High(AList.Items) do
  begin
    mItem := AList.Items[mSlot];
    if (mItem < 0) or ((AItems[mItem].Id <> '-') and not AItems[mItem].Visible) then
    begin
      Continue;
    end;
    if AItems[mItem].Id = '-' then
    begin
      if AList.Shown then
      begin
        mPending := mSlot;
      end;
      Continue;
    end;
    AList.Visible[mSlot] := True;
    AList.Shown := True;
    if mPending >= 0 then
    begin
      AList.Visible[mPending] := True;
    end;
    mPending := -1;
  end;
end;

class function TAtlasMenuSlots.Layout(const AItems: TArray<TAtlasSlotItem>; ATopCount, AGroupCount,
  AGroupSize: Integer): TAtlasSlotLayout;
var
  mIndex, mGroup: Integer;
begin
  Result := Default(TAtlasSlotLayout);
  Result.Top := NewList(ATopCount);
  SetLength(Result.Groups, AGroupCount);
  for mIndex := 0 to AGroupCount - 1 do
  begin
    Result.Groups[mIndex] := NewList(AGroupSize);
  end;
  for mIndex := 0 to High(AItems) do
  begin
    if AItems[mIndex].Section = '' then
    begin
      Place(Result.Top, mIndex, Result.Missing);
      Continue;
    end;
    mGroup := GroupOf(Result, AItems[mIndex].Section);
    if mGroup < 0 then
    begin
      Inc(Result.Missing);
      Continue;
    end;
    Place(Result.Groups[mGroup], mIndex, Result.Missing);
  end;
  Decide(Result.Top, AItems);
  for mIndex := 0 to High(Result.Groups) do
  begin
    Decide(Result.Groups[mIndex], AItems);
  end;
end;

class function TAtlasMenuSlots.MenuName(const APrefix: string; ANumber: Integer): string;
var
  mChar: Char;
begin
  Result := '';
  for mChar in APrefix do
  begin
    if CharInSet(mChar, ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
    begin
      Result := Result + mChar;
    end;
  end;
  if (Result = '') or not CharInSet(Result[1], ['A'..'Z', 'a'..'z', '_']) then
  begin
    Result := 'Atlas' + Result;
  end;
  Result := Result + IntToStr(Abs(ANumber));
end;

end.
