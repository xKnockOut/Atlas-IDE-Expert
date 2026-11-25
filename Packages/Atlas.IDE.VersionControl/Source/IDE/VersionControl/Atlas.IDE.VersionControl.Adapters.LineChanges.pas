unit Atlas.IDE.VersionControl.Adapters.LineChanges;

// Die Änderungsmarken und die Zeilenhistorie des Moduls für Base und Tracker (IAtlasLineChanges aus
// Atlas.IDE.Base.Foundation.LineChanges, #1905). Leitet an TAtlasIdeLineChanges weiter; die Komposition meldet
// den Adapter bei TAtlasLineChangeMarks an.

interface

uses
  Winapi.Windows,
  Atlas.Core.Editor.LineChanges,
  Atlas.IDE.Base.Foundation.LineChanges;

type
  /// <summary>Die Marken für Base und Tracker (IAtlasLineChanges, #1905).</summary>
  TAtlasLineChangesAdapter = class(TInterfacedObject, IAtlasLineChanges)
  public
    function Enabled: Boolean;
    procedure GoToChange(AForward: Boolean);
    function Snapshot(const AFileName: string; out AChanges: TAtlasLineChangeList; out ALineCount: Integer): Boolean;
    function BlameAt(AWnd: HWND; AX, AY: Integer; out ACommit: TAtlasBlameCommit): Boolean;
    procedure RefreshBlameTip;
    procedure HideBlameTip;
    procedure BlameHooksChanged;
  end;

implementation

uses
  Atlas.IDE.VersionControl.LineChanges;

{ TAtlasLineChangesAdapter }

function TAtlasLineChangesAdapter.Enabled: Boolean;
begin
  Result := TAtlasIdeLineChanges.Enabled;
end;

procedure TAtlasLineChangesAdapter.GoToChange(AForward: Boolean);
begin
  TAtlasIdeLineChanges.GoToChange(AForward);
end;

function TAtlasLineChangesAdapter.Snapshot(const AFileName: string; out AChanges: TAtlasLineChangeList;
  out ALineCount: Integer): Boolean;
begin
  Result := TAtlasIdeLineChanges.Snapshot(AFileName, AChanges, ALineCount);
end;

function TAtlasLineChangesAdapter.BlameAt(AWnd: HWND; AX, AY: Integer; out ACommit: TAtlasBlameCommit): Boolean;
begin
  Result := TAtlasIdeLineChanges.BlameAt(AWnd, AX, AY, ACommit);
end;

procedure TAtlasLineChangesAdapter.RefreshBlameTip;
begin
  TAtlasIdeLineChanges.RefreshBlameTip;
end;

procedure TAtlasLineChangesAdapter.HideBlameTip;
begin
  TAtlasIdeLineChanges.HideBlameTip;
end;

procedure TAtlasLineChangesAdapter.BlameHooksChanged;
begin
  TAtlasIdeLineChanges.SetBlameHooks(TAtlasLineChangeMarks.BlameHooks);
end;

end.
