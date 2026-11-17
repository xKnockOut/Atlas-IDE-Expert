unit Atlas.UI.Foundation.ListBox;

// Liste (TListBox) für Atlas-Fenster, die beim Neuzeichnen nicht flackert.
// Unter dem Thema der IDE hängt an jeder TListBox ein Stil. Der zeichnet die
// ganze Liste neu, sobald sie den Fokus bekommt oder verliert (Klick in die
// Liste, Sprung in den Editor nach der Auswahl), und füllt dabei zuerst die
// Fläche am Bildschirm in der Grundfarbe, an der Doppelpufferung vorbei;
// danach kommen die Zeilen: Die Liste blitzt kurz leer auf.
// TAtlasListBox ist doppelt gepuffert und übergeht das Löschen am Bildschirm
// in WndProc, bevor der Stil es sieht. Das Löschen in den Puffer (wParam =
// lParam, aus TWinControl.WMPaint) bleibt beim Üblichen, so behält die Fläche
// unter der letzten Zeile ihre Farbe.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.Classes,
  Vcl.StdCtrls;

type
  TAtlasListBox = class(TListBox)
  protected
    /// <summary>Löschen des Hintergrunds am Bildschirm übergehen; gezeichnet wird über den Puffer.</summary>
    procedure WndProc(var Message: TMessage); override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Löscht WM_ERASEBKGND mit diesen Parametern den Hintergrund? Nur beim Zeichnen in den Puffer
    /// (wParam = lParam).</summary>
    class function ErasesBackground(AWParam: WPARAM; ALParam: LPARAM): Boolean; static;
  end;

implementation

{ TAtlasListBox }

constructor TAtlasListBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  DoubleBuffered := True;
end;

class function TAtlasListBox.ErasesBackground(AWParam: WPARAM; ALParam: LPARAM): Boolean;
begin
  Result := AWParam = WPARAM(ALParam);
end;

procedure TAtlasListBox.WndProc(var Message: TMessage);
begin
  // Vor inherited: Dort sieht der Stil der IDE die Nachricht zuerst und füllte die Fläche am Bildschirm.
  if (Message.Msg = WM_ERASEBKGND) and DoubleBuffered and not ErasesBackground(Message.WParam, Message.LParam) then
  begin
    Message.Result := 1;
    Exit;
  end;
  inherited WndProc(Message);
end;

end.
