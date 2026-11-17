unit Atlas.UI.Debug.ExceptionsParts;

// Teile des Fensters „Exception-Verlauf“ (#517) neben Liste und Stapel, reine
// VCL:
//   - TAtlasDebugExceptionsHooks: was der Frame an die IDE-Schicht meldet; ein
//     Objekt, das sich Frame und Kontextmenü teilen.
//   - TAtlasDebugExceptionsFilterBar: Leiste oben mit der Auswahl der Klasse
//     („Alle Klassen“ oder eine aus dem Verlauf) und dem Textfilter. Sie merkt
//     sich die Klassen, die die Auswahl zeigt, damit die gewählte Klasse auch
//     nach einem neuen Verlauf stimmt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Debug.Exceptions;

type
  /// <summary>Was der Frame an die IDE-Schicht meldet; nicht gesetzte Einträge bleiben still. Gehört dem Frame.
  /// </summary>
  TAtlasDebugExceptionsHooks = class
  private
    FOpen: TProc<TAtlasDebugException>;
    FCopy: TProc<TAtlasDebugException>;
    FIgnoreClass: TProc<string, Boolean>;
    FClear: TProc;
  public
    /// <summary>Zur Stelle springen; nur für Einträge mit Quelltext.</summary>
    property Open: TProc<TAtlasDebugException> read FOpen write FOpen;
    property Copy: TProc<TAtlasDebugException> read FCopy write FCopy;
    /// <summary>Klasse und True = künftig ignorieren, False = wieder anhalten.</summary>
    property IgnoreClass: TProc<string, Boolean> read FIgnoreClass write FIgnoreClass;
    /// <summary>Verlauf leeren.</summary>
    property Clear: TProc read FClear write FClear;
  end;

  /// <summary>Auswahl der Klasse und Textfilter über der Liste.</summary>
  TAtlasDebugExceptionsFilterBar = class(TPanel)
  private
    FClassBox: TComboBox;
    FFilter: TEdit;
    /// <summary>Klassen in der Auswahl, ohne „Alle Klassen“.</summary>
    FClasses: TArray<string>;
  public
    /// <summary>AFrame ist Besitzer und Elternfenster; seine Auflösung bestimmt die Größen. AChange meldet jede
    /// Änderung von Klasse oder Filter, AKeyDown die Tasten im Filter.</summary>
    constructor CreateIn(AFrame: TWinControl; AChange: TNotifyEvent; AKeyDown: TKeyEvent);
    /// <summary>Auswahl mit AClasses füllen; die gewählte Klasse bleibt, wenn es sie noch gibt. Braucht ein Fenster
    /// (TComboBox.Items).</summary>
    procedure FillClasses(const AClasses: TArray<string>);
    /// <summary>Gewählte Klasse; '' für „Alle Klassen“.</summary>
    function SelectedClass: string;
    property ClassBox: TComboBox read FClassBox;
    property Filter: TEdit read FFilter;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.UI.Debug.Exceptions.Strings;

const
  /// <summary>Höhe der Leiste bei 96 dpi.</summary>
  cBarHeight = 30;
  /// <summary>Breite der Auswahl der Klasse bei 96 dpi.</summary>
  cClassBoxWidth = 170;

{ TAtlasDebugExceptionsFilterBar }

constructor TAtlasDebugExceptionsFilterBar.CreateIn(AFrame: TWinControl; AChange: TNotifyEvent;
  AKeyDown: TKeyEvent);
begin
  inherited Create(AFrame);
  Parent := AFrame;
  Align := alTop;
  BevelOuter := bvNone;
  ShowCaption := False;
  ParentBackground := True;
  Height := MulDiv(cBarHeight, AFrame.CurrentPPI, 96);

  FClassBox := TComboBox.Create(Self);
  FClassBox.Parent := Self;
  FClassBox.Align := alLeft;
  FClassBox.AlignWithMargins := True;
  FClassBox.Style := csDropDownList;
  FClassBox.Width := MulDiv(cClassBoxWidth, AFrame.CurrentPPI, 96);
  FClassBox.OnChange := AChange;

  FFilter := TEdit.Create(Self);
  FFilter.Parent := Self;
  FFilter.Align := alClient;
  FFilter.AlignWithMargins := True;
  FFilter.TextHint := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugExceptionsFilterHint);
  FFilter.OnChange := AChange;
  FFilter.OnKeyDown := AKeyDown;
end;

procedure TAtlasDebugExceptionsFilterBar.FillClasses(const AClasses: TArray<string>);
var
  mKeep, mName: string;
  mIndex: Integer;
begin
  mKeep := SelectedClass;
  FClasses := AClasses;
  FClassBox.Items.BeginUpdate;
  try
    FClassBox.Items.Clear;
    FClassBox.Items.Add(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugExceptionsAllClasses));
    for mName in FClasses do
    begin
      FClassBox.Items.Add(mName);
    end;
  finally
    FClassBox.Items.EndUpdate;
  end;
  FClassBox.ItemIndex := 0;
  for mIndex := 0 to High(FClasses) do
  begin
    if SameText(FClasses[mIndex], mKeep) then
    begin
      FClassBox.ItemIndex := mIndex + 1;
    end;
  end;
end;

function TAtlasDebugExceptionsFilterBar.SelectedClass: string;
begin
  Result := '';
  if (FClassBox.ItemIndex > 0) and (FClassBox.ItemIndex <= Length(FClasses)) then
  begin
    Result := FClasses[FClassBox.ItemIndex - 1];
  end;
end;

end.
