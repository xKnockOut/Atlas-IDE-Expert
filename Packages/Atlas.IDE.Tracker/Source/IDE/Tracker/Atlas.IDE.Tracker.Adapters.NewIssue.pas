unit Atlas.IDE.Tracker.Adapters.NewIssue;

// „Issue anlegen“ für Base (#1268, #1355), Rolle Adapters: TAtlasIdeIssueCreation
// erfüllt IAtlasIssueCreation aus Atlas.Core.Modules.Contract, wandelt die
// Records des Vertrags und ruft TAtlasIdeNewIssue (Atlas.IDE.Tracker.NewIssue).
// Anlegen nur in der Komposition des Moduls.

interface

uses
  Atlas.Core.Modules.Contract;

type
  /// <summary>„Issue anlegen“ für Base (#1268, #1355): wandelt die Records des Vertrags und ruft
  /// TAtlasIdeNewIssue; ohne Start bzw. mit issues.create aus wirkungslos. Hauptthread.</summary>
  TAtlasIdeIssueCreation = class(TInterfacedObject, IAtlasIssueCreation)
  public
    function Enabled: Boolean;
    procedure FromFindings(const AFindings: TArray<TAtlasIssueFinding>);
    procedure FromCrash(const ATitle, ADescription: string; const AFiles: TArray<TAtlasIssueTextFile>);
  end;

implementation

uses
  Atlas.Core.Tracker.NewIssue,
  Atlas.Core.Tracker.Attach,
  Atlas.IDE.Tracker.NewIssue;

{ TAtlasIdeIssueCreation }

function TAtlasIdeIssueCreation.Enabled: Boolean;
begin
  Result := TAtlasIdeNewIssue.Enabled;
end;

procedure TAtlasIdeIssueCreation.FromFindings(const AFindings: TArray<TAtlasIssueFinding>);
var
  mItems: TArray<TAtlasNewIssueFinding>;
  mIndex: Integer;
begin
  if not Enabled then
  begin
    Exit;
  end;
  SetLength(mItems, Length(AFindings));
  for mIndex := 0 to High(AFindings) do
  begin
    mItems[mIndex] := TAtlasNewIssueFinding.Create(AFindings[mIndex].Rule, AFindings[mIndex].Message,
      AFindings[mIndex].Location, AFindings[mIndex].LineText);
  end;
  TAtlasIdeNewIssue.FromFindings(mItems);
end;

procedure TAtlasIdeIssueCreation.FromCrash(const ATitle, ADescription: string;
  const AFiles: TArray<TAtlasIssueTextFile>);
var
  mFiles: TArray<TAtlasAttachFile>;
  mIndex: Integer;
begin
  if not Enabled then
  begin
    Exit;
  end;
  SetLength(mFiles, Length(AFiles));
  for mIndex := 0 to High(AFiles) do
  begin
    mFiles[mIndex] := TAtlasAttachFile.CreateText(TAtlasAttachKind.LogFile, AFiles[mIndex].Name, AFiles[mIndex].Text);
  end;
  TAtlasIdeNewIssue.FromCrash(ATitle, ADescription, mFiles);
end;

end.
