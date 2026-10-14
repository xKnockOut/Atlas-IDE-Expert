object HauptFormular: THauptFormular
  Left = 0
  Top = 0
  Caption = 'Referenz'
  ClientHeight = 400
  ClientWidth = 600
  OnCreate = FormCreate
  inline Suche: TSuchrahmen
    Left = 0
    Top = 0
    Width = 600
    Height = 33
    Align = alTop
    TabOrder = 0
  end
  object KundenListe: TListBox
    Left = 0
    Top = 33
    Width = 600
    Height = 326
    Align = alClient
    ItemHeight = 15
    TabOrder = 1
  end
  object DetailButton: TButton
    Left = 8
    Top = 368
    Width = 75
    Height = 25
    Caption = 'Detail'
    TabOrder = 2
    OnClick = DetailButtonClick
  end
end
