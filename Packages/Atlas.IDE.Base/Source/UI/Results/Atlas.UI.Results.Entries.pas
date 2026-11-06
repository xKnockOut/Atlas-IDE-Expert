unit Atlas.UI.Results.Entries;

// Fundstellen im Ergebnisfenster (#400): nach Unit gruppiert, je Zeile „Zeile: Text“, alle Gruppen aufgeklappt.
// Verwendungen mit erschlossenen Treffern (#1119) stehen in zwei Abschnitten, „Sicher (n)“ und „Erschlossen (n) ·
// vor dem Umbenennen prüfen“, darin nach Unit gruppiert; erschlossene Zeilen tragen ≈ und ihren Grund, der Hinweis
// unter der Maus erklärt ihn. „Nur sichere“ in der Titelzeile blendet die erschlossenen aus.

interface

uses
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Atlas.Core.Results.Model,
  Atlas.UI.Results.View;

type
  TAtlasResultsEntriesPart = class(TAtlasResultsPart)
  private type
    TRated = record
      Title: string;
      Entries: TArray<TAtlasResultEntry>;
      SureCaption: string;
      InferredCaption: string;
    end;
  private
    FOnlySure: TCheckBox;
    FRated: TRated;
    procedure RenderRated;
    procedure AddSection(const ACaption: string; const AEntries: TArray<TAtlasResultEntry>);
    procedure OnlySureClick(Sender: TObject);
  protected
    procedure Reset; override;
  public
    constructor Create(AView: TAtlasResultsView);
    /// <summary>Fundstellen unter AParent, je Unit eine aufgeklappte Gruppe.</summary>
    procedure AddGroups(AParent: TTreeNode; const AGroups: TArray<TAtlasResultGroup>);
    /// <summary>Fundstellen nach Unit gruppiert; alle Gruppen aufgeklappt.</summary>
    procedure Show(const ATitle: string; const AGroups: TArray<TAtlasResultGroup>);
    /// <summary>Fundstellen nach Treffersicherheit (#1119): ohne erschlossene wie Show; sonst zwei Abschnitte mit
    /// ASureCaption bzw. AInferredCaption (Format mit der Anzahl), darin nach Unit gruppiert.</summary>
    procedure ShowRated(const ATitle: string; const AEntries: TArray<TAtlasResultEntry>;
      const ASureCaption, AInferredCaption: string);
    /// <summary>„Nur sichere“ (#1119); sichtbar, solange erschlossene Treffer da sind.</summary>
    property OnlySure: TCheckBox read FOnlySure;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Controls,
  Atlas.UI.Strings,
  Atlas.UI.Results.Texts;

{ TAtlasResultsEntriesPart }

constructor TAtlasResultsEntriesPart.Create(AView: TAtlasResultsView);
begin
  inherited Create(AView);
  // Filter „Nur sichere“ (#1119), rechts in der Titelzeile.
  FOnlySure := TAtlasResultsControls.Check(AView.Host, AView.Header, alRight, 110,
    TAtlasStrings.Text(TAtlasTextId.ResultsOnlySure), OnlySureClick);
  FOnlySure.Visible := False;
end;

procedure TAtlasResultsEntriesPart.Reset;
begin
  FOnlySure.Visible := False;
end;

procedure TAtlasResultsEntriesPart.AddGroups(AParent: TTreeNode; const AGroups: TArray<TAtlasResultGroup>);
var
  mGroup: TAtlasResultGroup;
  mEntry: TAtlasResultEntry;
  mData: TAtlasResultsNode;
  mGroupNode: TTreeNode;
begin
  for mGroup in AGroups do
  begin
    mData := TAtlasResultsNode.Create(TAtlasResultsNodeKind.Group);
    mData.FileName := mGroup.FileName;
    mGroupNode := View.AddNode(AParent, mGroup.Caption, mData);
    for mEntry in mGroup.Entries do
    begin
      mData := TAtlasResultsNode.Place(TAtlasResultsNodeKind.Entry, mEntry.FileName, mEntry.Line, mEntry.Character);
      mData.Hint := mEntry.Confidence.Explanation;
      View.AddNode(mGroupNode, TAtlasResultsTexts.EntryText(mEntry), mData);
    end;
    mGroupNode.Expand(False);
  end;
end;

procedure TAtlasResultsEntriesPart.Show(const ATitle: string; const AGroups: TArray<TAtlasResultGroup>);
begin
  View.Clear(ATitle);
  View.Tree.Items.BeginUpdate;
  try
    AddGroups(nil, AGroups);
  finally
    View.Tree.Items.EndUpdate;
  end;
  View.Select(nil);
end;

procedure TAtlasResultsEntriesPart.ShowRated(const ATitle: string; const AEntries: TArray<TAtlasResultEntry>;
  const ASureCaption, AInferredCaption: string);
begin
  FRated.Title := ATitle;
  FRated.Entries := AEntries;
  FRated.SureCaption := ASureCaption;
  FRated.InferredCaption := AInferredCaption;
  RenderRated;
end;

procedure TAtlasResultsEntriesPart.AddSection(const ACaption: string; const AEntries: TArray<TAtlasResultEntry>);
var
  mSection: TTreeNode;
begin
  mSection := View.AddNode(nil, Format(ACaption, [Length(AEntries)]),
    TAtlasResultsNode.Create(TAtlasResultsNodeKind.Placeholder));
  AddGroups(mSection, TAtlasResults.Group(AEntries));
  mSection.Expand(False);
end;

procedure TAtlasResultsEntriesPart.RenderRated;
var
  mSure, mInferred: TArray<TAtlasResultEntry>;
  mEntry: TAtlasResultEntry;
begin
  mSure := TAtlasResults.SureOnly(FRated.Entries);
  mInferred := nil;
  for mEntry in FRated.Entries do
  begin
    if mEntry.Confidence.Inferred then
    begin
      mInferred := mInferred + [mEntry];
    end;
  end;
  if Length(mInferred) = 0 then
  begin
    Show(FRated.Title, TAtlasResults.Group(FRated.Entries));
    Exit;
  end;
  View.Clear(FRated.Title);
  FOnlySure.Visible := True;
  View.Tree.Items.BeginUpdate;
  try
    if FOnlySure.Checked then
    begin
      AddGroups(nil, TAtlasResults.Group(mSure));
    end
    else
    begin
      AddSection(FRated.SureCaption, mSure);
      AddSection(FRated.InferredCaption, mInferred);
    end;
  finally
    View.Tree.Items.EndUpdate;
  end;
  View.Select(nil);
end;

procedure TAtlasResultsEntriesPart.OnlySureClick(Sender: TObject);
begin
  // Clear blendet den Filter aus und RenderRated wieder ein; Checked bleibt.
  if Length(FRated.Entries) > 0 then
  begin
    RenderRated;
  end;
end;

end.
