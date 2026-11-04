unit Atlas.UI.Notes.List;

// Liste der Notizen (#545) im Ergebnisfenster: macht aus den Gruppen eines
// Notizbuchs eine allgemeine Liste mit Kennungen (TAtlasResultsItemList, seit
// #1455; vorher kannte das Ergebnisfenster die Notizen selbst). Je Datei eine
// Gruppe „Kunde.pas (2)“ mit Einträgen „42: Titel“, verwaiste am Ende als
// „Verwaist (1)“ mit „Kunde.pas, Zeile 42: Titel“.

interface

uses
  Atlas.Core.Notes.Store,
  Atlas.UI.Results.Items;

type
  TAtlasNotesList = class
  public const
    /// <summary>Besitzer der Liste im Ergebnisfenster.</summary>
    Owner = 'notes';
  public
    /// <summary>Gruppe: "Kunde.pas (2)" bzw. "Verwaist (1)".</summary>
    class function GroupText(const AGroup: TAtlasNoteGroup): string; static;
    /// <summary>Eintrag: "42: Titel" bzw. verwaist "Kunde.pas, Zeile 42: Titel".</summary>
    class function NoteText(const ANote: TAtlasNote; AOrphaned: Boolean): string; static;
    /// <summary>Liste für das Ergebnisfenster; ASelectId: diese Notiz wählen ('' = die erste).</summary>
    class function Build(const ATitle: string; const AGroups: TArray<TAtlasNoteGroup>; const ASelectId: string;
      const AOnEdit, AOnDelete: TAtlasResultsItemAction): TAtlasResultsItemList; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Bookmarks.Strings;

class function TAtlasNotesList.GroupText(const AGroup: TAtlasNoteGroup): string;
begin
  if AGroup.Orphaned then
  begin
    Result := Format(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.NotesOrphanGroup), [Length(AGroup.Notes)]);
  end
  else
  begin
    Result := Format('%s (%d)', [ExtractFileName(AGroup.FileName), Length(AGroup.Notes)]);
  end;
end;

class function TAtlasNotesList.NoteText(const ANote: TAtlasNote; AOrphaned: Boolean): string;
begin
  if AOrphaned then
  begin
    Result := Format(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.NotesOrphanEntry),
      [ExtractFileName(ANote.FileName),
      ANote.Line + 1, ANote.Title]);
  end
  else
  begin
    Result := Format('%d: %s', [ANote.Line + 1, ANote.Title]);
  end;
end;

class function TAtlasNotesList.Build(const ATitle: string; const AGroups: TArray<TAtlasNoteGroup>;
  const ASelectId: string; const AOnEdit, AOnDelete: TAtlasResultsItemAction): TAtlasResultsItemList;
var
  mGroup: TAtlasNoteGroup;
  mNote: TAtlasNote;
  mItemGroup: TAtlasResultsItemGroup;
  mItem: TAtlasResultsItem;
begin
  Result := Default(TAtlasResultsItemList);
  Result.Owner := Owner;
  Result.Title := ATitle;
  Result.SelectId := ASelectId;
  Result.EditCaption := TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.NotesEdit);
  Result.DeleteCaption := TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.NotesDelete);
  Result.OnEdit := AOnEdit;
  Result.OnDelete := AOnDelete;
  for mGroup in AGroups do
  begin
    mItemGroup := Default(TAtlasResultsItemGroup);
    mItemGroup.Caption := GroupText(mGroup);
    mItemGroup.FileName := mGroup.FileName;
    for mNote in mGroup.Notes do
    begin
      mItem := Default(TAtlasResultsItem);
      mItem.Id := mNote.Id;
      mItem.Caption := NoteText(mNote, mGroup.Orphaned);
      mItem.FileName := mNote.FileName;
      mItem.Line := mNote.Line;
      mItemGroup.Items := mItemGroup.Items + [mItem];
    end;
    Result.Groups := Result.Groups + [mItemGroup];
  end;
end;

end.
