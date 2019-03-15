ODS("Script~C0A 'pproc.lua'~C07 executed in thread~C0E "..thread_name.."~C07")

-- available globals:
--  def_layer_thickness  (float)
--  def_exposure_time    (float)
--  def_off_time         (float)
--  def_bottom_time      (float)
--  bottom_layers        (int)
--  def_coarse_neighbors (int)
--  program_code         (char)
--  photon_file          (object)
--  layer                (object)

function process_layer()
 if program_code == 'c' then
   layer.exp_time = 4.5 -- this not affected???
   -- more steps - erasing more edges
   layer:coarse()
   layer:coarse()
   layer:coarse()
   -- lower half of layer, for testing
    
   -- layer:coarse(def_coarse_neighbors, 0, 1280, 1438, 2558) 
   -- layer:coarse(def_coarse_neighbors, 0, 1280, 1438, 2558) 
   -- layer:coarse(def_coarse_neighbors, 0, 1280, 1438, 2558) 
 else
   ODS(string.format("unsupported program code [%s]", program_code))    
 end   
end