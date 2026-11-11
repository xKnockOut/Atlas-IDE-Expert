unit Atlas.UI.Designer.Dialog;

// Gemeinsames Gerüst der kleinen Dialoge des Designers, reine VCL: Schrift
// (Segoe UI 9), Rahmen, Position, Breite und Zeilen von oben nach unten.
// Die Dialoge erben davon statt dieselben Zeilen je Dialog zu wiederholen.

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ExtCtrls;

type
  TAtlasDesignerDialog = class(TForm)
  protected const
    /// <summary>Abstand zwischen Rand, Zeilen und Knöpfen (vor dem Skalieren).</summary>
    cGap = 10;
    /// <summary>Schriftgröße der Dialoge in Punkt.</summary>
    cFontSize = 9;
  protected
    /// <summary>Titel, Rahmen ABorder, Position, Schrift und Breite AWidth (vor dem Skalieren).</summary>
    procedure InitDialog(const ACaption: string; AWidth: Integer; ABorder: TFormBorderStyle);
    /// <summary>Neue Zeile unter allen bisherigen (alTop, Höhe nach Inhalt).</summary>
    function AddRow: TFlowPanel;
    /// <summary>Beschriftung ACaption in AParent, auf Höhe des Texts eines Eingabefelds daneben.</summary>
    procedure AddLabel(AParent: TWinControl; const ACaption: string);
  end;

implementation

uses
  Vcl.StdCtrls;

const
  cFontName = 'Segoe UI';
  /// <summary>Top einer neuen Zeile weit unter allen bisherigen; alTop ordnet nach Top.</summary>
  cBehindAllRows = 2000;
  /// <summary>Abstand der Beschriftung nach oben, damit sie auf der Textzeile eines Eingabefelds steht.</summary>
  cLabelTop = 3;

procedure TAtlasDesignerDialog.InitDialog(const ACaption: string; AWidth: Integer; ABorder: TFormBorderStyle);
begin
  Caption := ACaption;
  BorderStyle := ABorder;
  Position := poMainFormCenter;
  Font.Name := cFontName;
  Font.Size := cFontSize;
  ClientWidth := ScaleValue(AWidth);
  Canvas.Font := Font;
end;

function TAtlasDesignerDialog.AddRow: TFlowPanel;
begin
  Result := TFlowPanel.Create(Self);
  Result.Parent := Self;
  Result.Align := alTop;
  Result.AutoSize := True;
  Result.BevelOuter := bvNone;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(cGap, cGap div 2, cGap, 0);
  Result.Top := ScaleValue(cBehindAllRows) + ComponentCount;
end;

procedure TAtlasDesignerDialog.AddLabel(AParent: TWinControl; const ACaption: string);
var
  mLabel: TLabel;
begin
  mLabel := TLabel.Create(Self);
  mLabel.Parent := AParent;
  mLabel.Caption := ACaption;
  mLabel.AlignWithMargins := True;
  mLabel.Margins.SetBounds(0, ScaleValue(cLabelTop), cGap div 2, 0);
end;

end.
