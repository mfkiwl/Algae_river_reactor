
## LOAD PARAMETERS
## Options:
#   Load default parameters
#   Load parameters from an Excel file

using Debugger
using BasicInterpolators
break_on(:error)

function LoadDefaultParameters(l, q)
    ## PDE Discretization
    num_odes_y = 100
    num_odes_z = 11
    time_end = 732       #hours
  
    ## Physical Constants
    reference_temperature = 20.0                                        # deg Celsius
    reference_pressure = 101315.0                                       # Pascals
    stefan_boltzmann_constant = 5.67037442E-08                          # W / m^2 / K^4

    #Temperature Constants
    input_temperature = 293.15                          # Kelvin
    ground_temperature = 290.0                          # Kelvin
    
    # Air Properties
    density_air(T) = reference_pressure ./ (287.058 .* T)                 # kg/m3, T in K
    dynamic_viscosity_air(T) = 1.458E-06 .* (T.^1.5) ./ (T .+ 110.4)        # Pa sec [kg/m/sec]
    thermal_conductivity_air(T) = 0.02624 .* (T/300).^0.8646              # W/m*K
    specific_heat_capacity_air(T) = 1002.5 .+ (275E-06) .* (T .- 200).^2      # J/kg*K
    prandtl_air(T) = specific_heat_capacity_air(T) .* dynamic_viscosity_air(T) ./ thermal_conductivity_air(T)             # dimensionless
    emissivity_air = 0.80                                               # dimensionless
   

    # Water Properties
    density_water_20degC = 998.2071                                             # kg / m^3
    expansion_coefficient_water = 0.0002                                        # 1/degC
    density_water(T) = density_water_20degC ./ (1 .+ expansion_coefficient_water .* (T .- (reference_temperature+273)))   #kg/m^3
    dynamic_viscosity_water(T) = (2.414E−05 .* 10^( 247.8 ./ (T .-140)))*3600         # [kg/m/hr]
    
    Ar = 5.328  #unitless
    B = -6.913 * 10 ^ (-3) #unitless
    C = 9.6 * 10 ^ (-6) #unitless
    D = 2.5 * 10 ^ (-9) #unitless
    specific_heat_capacity_water(T) = 1000*(Ar + B*T + C*(T^2) + D*(T^3)) #J/kg/K
    #above information obtained from: 
    #K.G. Nayar, M.H. Sharqawy, L.D. Banchik, and J.H. Lienhard V, "Thermophysical properties of seawater: A review and new correlations that include pressure dependence," Desalination, Vol. 390, pp.1-24, 2016. doi:10.1016/j.desal.2016.02.024 (preprint)

    thermal_conductivity_water(T) = (0.565464 .+ 1.756E-03 .* T .- 6.46E-06 .* T.^2)*3600   # J/m/K/hr
    solar_reflectance_water = 0.1357 # fraction of light reflected
    diffusion_coeff_water_air(T) = 22.5E-06 .* ( (T .+ 273.15) ./ 273.15).^1.8*3600        # m^2 / sec
    saturated_vapor_pressure_water_air(T) = (exp(77.3450+0.0057*T-7235/T))/(T^8.2)  #Pascals, always use dry bulb temp
    heat_vaporization_water = 2430159                                        # J / kg, T = 30 degC            [40660 * ( (647.3 - (T + 273.15)) / (647.3 - 373.2))^0.38 #J/mole, but isn't very accurate]
    emissivity_water = 0.97                                                     # dimensionless

    # CO2 Properties
    diffusion_coeff_co2_water(T) = (13.942E-09*((293/227.0) - 1)^1.7094)*3600              # m^2 / hr [equation fitted based on data in https://pubs.acs.org/doi/10.1021/je401008s]
    solubility_co2_water(T) = (0.00025989 .* (T .- 273.15).^2 .- 0.03372247 .* (T .- 273.15) .+ 1.31249383) ./ 1000.0  #mole fraction of dissolved CO2 in water at equilibrium [equation fitted based on data from https://srd.nist.gov/JPCRD/jpcrd427.pdf]
    co2_init = 0.4401 #g/m3
    DIC_init = 2002 #uM

    # Construction Material Properties
    thermal_diffusivity_concrete = 1011.83E0-9                                  #
    thermal_conductivity_concrete = 1.3                                         # W / m / K

    ## Geographic Properties -- Seasonal and daily variations
    global_horizontal_irradiance_data = zeros(8760,1)   # W/m^2
    ambient_temperature_data = zeros(8760,1)            # deg Celsius
    relative_humidity_data = zeros(8760,1)              # percent humidity
    wind_speed_data = zeros(8760,1)                     # m/s

    # Reading Measured GHI Values from Pheonix, AZ [stored in "722789TYA.csv"]
    csv_reader = CSV.File("722789TYA.csv", skipto=3, header=["col1", "col2", "col3", "col4", "col5", "col6","col7", "col8", "col9", "col10", "col11", "col12","col13", "col14", "col15", "col16", "col17", "col18","col19", "col20", "col21", "col22", "col23", "col24","col25", "col26", "col27", "col28", "col29", "col30","col31", "col32", "col33", "col34", "col35", "col36","col37", "col38", "col39", "col40", "col41", "col42","col43", "col44", "col45", "col46", "col47"])
    for (i,row) in enumerate(csv_reader)
        #days_data[i] = row.col1                         # days
        #times_data[i] = row.col2                        # hours
        global_horizontal_irradiance_data[i] = convert(Float64, row.col5)     # W/m^2
        ambient_temperature_data[i] = convert(Float64, row.col32) + 273.15    # Kelvin
        relative_humidity_data[i] = convert(Float64, row.col38)               # percent humidity
        wind_speed_data[i]= convert(Float64, row.col47)                       # m/s
    end

    data_begin = 4345 #July 1st

    ## River Reactor Geometric Properties

    lengths = [200,200,200,200,200,200,200,200]                           # meters
    reactor_length = 200
    real_length = lengths[q]
    reactor_width =  0.5                               # meters
    reactor_initial_liquid_level = 0.15             # meters, this is the sluice gate inlet height

    #Evaporation Equations

    evaporation_constant(W) = 25 +19*W #kg dry air/m2-hr
    ambient_humidity_ratio(R_H, P) = 0.62198*(P*(R_H/100))/(reference_pressure-(P*(R_H/100))) #kg H2O/ kg dry air
    surface_humidity_ratio(T) = 0.62198*(saturated_vapor_pressure_water_air(T)/(reference_pressure-saturated_vapor_pressure_water_air(T))) #kg H2O/kg dry air
    evaporation_mass_flux(T,W,R_H,P) = evaporation_constant(W)*(surface_humidity_ratio(T)-ambient_humidity_ratio(R_H, P)) #kg H2O/m2-hr
    evaporation_heat_flux(T,W,R_H,P) = evaporation_mass_flux(T,W,R_H,P)*heat_vaporization_water #J/hr-m2
    ## above equations obtained from https://www.engineeringtoolbox.com/evaporation-water-surface-d_690.html 

    #Flow and Velocity Profiles
    flow_rates = [5,10,15,20,25,30,35,40] #m3/hr
    volumetric_flow_rate_o = flow_rates[l] #m^3/hr
    volumetric_flow_rate_strip = volumetric_flow_rate_o/20 #m3/hr
    strip_position = [0,5,10,15,20,25,30,35,40,45,50,55,60,65,70,75,80,85,90,95,100] #20 dispersed columns
    s_conc = [30,60,90,120,150,180,210,240] #g/m3 co2
    strip_concentration = s_conc[q] #g/m3, saturated
    
    volumetric_flow_rate(T,W,R_H,P,x) = (max((volumetric_flow_rate_o -evaporation_mass_flux(T,W,R_H,P)*(reactor_width/density_water(T))*x*(reactor_length/num_odes_y)),0) 
    + volumetric_flow_rate_strip*(max(x-(strip_position[1]-1),0)/max(abs(x-(strip_position[1]-1)),1))
    + volumetric_flow_rate_strip*(max(x-(strip_position[2]-1),0)/max(abs(x-(strip_position[2]-1)),1))
    + volumetric_flow_rate_strip*(max(x-(strip_position[3]-1),0)/max(abs(x-(strip_position[3]-1)),1))
    + volumetric_flow_rate_strip*(max(x-(strip_position[4]-1),0)/max(abs(x-(strip_position[4]-1)),1))
    + volumetric_flow_rate_strip*(max(x-(strip_position[5]-1),0)/max(abs(x-(strip_position[5]-1)),1))
    + volumetric_flow_rate_strip*(max(x-(strip_position[6]-1),0)/max(abs(x-(strip_position[6]-1)),1))
    + volumetric_flow_rate_strip*(max(x-(strip_position[7]-1),0)/max(abs(x-(strip_position[7]-1)),1))
    + volumetric_flow_rate_strip*(max(x-(strip_position[8]-1),0)/max(abs(x-(strip_position[8]-1)),1))
    + volumetric_flow_rate_strip*(max(x-(strip_position[9]-1),0)/max(abs(x-(strip_position[9]-1)),1))
    + volumetric_flow_rate_strip*(max(x-(strip_position[10]-1),0)/max(abs(x-(strip_position[10]-1)),1))
    + volumetric_flow_rate_strip*(max(x-(strip_position[11]-1),0)/max(abs(x-(strip_position[11]-1)),1))
    + volumetric_flow_rate_strip*(max(x-(strip_position[12]-1),0)/max(abs(x-(strip_position[12]-1)),1))
    + volumetric_flow_rate_strip*(max(x-(strip_position[13]-1),0)/max(abs(x-(strip_position[13]-1)),1))
    + volumetric_flow_rate_strip*(max(x-(strip_position[14]-1),0)/max(abs(x-(strip_position[14]-1)),1))
    + volumetric_flow_rate_strip*(max(x-(strip_position[15]-1),0)/max(abs(x-(strip_position[15]-1)),1))
    + volumetric_flow_rate_strip*(max(x-(strip_position[16]-1),0)/max(abs(x-(strip_position[16]-1)),1))
    + volumetric_flow_rate_strip*(max(x-(strip_position[17]-1),0)/max(abs(x-(strip_position[17]-1)),1))
    + volumetric_flow_rate_strip*(max(x-(strip_position[18]-1),0)/max(abs(x-(strip_position[18]-1)),1))
    + volumetric_flow_rate_strip*(max(x-(strip_position[19]-1),0)/max(abs(x-(strip_position[19]-1)),1))
    + volumetric_flow_rate_strip*(max(x-(strip_position[20]-1),0)/max(abs(x-(strip_position[20]-1)),1))
    )

    height(T,S,R_H,W,P,x) = volumetric_flow_rate(T,W,R_H,P,x)/(S*reactor_width)
    term(V,H) = V/((2/3)*H^2)
    velocity_profile_lam(V,y,H) = term(V,H)*((H-y*(H/num_odes_z))*H + 0.5*(H-y*(H/num_odes_z))^2)
    hydraulic_diameter(H) = 4 * (reactor_width * H) / (reactor_width + 2 * H) #m
    reynolds_number(H,T,V) = V .* density_water(T) .* hydraulic_diameter(H) ./ (dynamic_viscosity_water(T))
    

    ## Biomass Properties
    input_biomass_concentration = 1000.0 / 1000.0         # kg/m^3
    max_biomass_specific_growth_rate = 7.9/24   # 1 / hour (obtained from Krishnan at T_opt, 35 salinity)
    co2_per_biomass = 1.88   #kg CO2/kg algae
    biomass_diffusion_coefficient_y = 1.0e-9 * 3600.0           #m^2/hour
    biomass_diffusion_coefficient_z = 1.0e-9 * 3600.0           #m^2/hour

    #Biomass Growth Adjustment Factors
    salinity_factor(S) = -0.0002*S^2 + 0.0107*S + 0.8661 #unitless, S in kg/kg sw
    ## obtained from 2-degree polynomial fit of data obtained from Krishnan et al.

    T_opt = 308 #in C, optimum temperature
    T_min = 277.2 #in C, minimum temperature
    T_max = 320 #in C, maximum temperature
    temperature_factor_g(T) = (T_opt-T_min)*(T-T_opt) #unitless
    temperature_factor_f(T) = (T_opt-T_max)*(T_opt+T_min-2*(T)) #unitless
    temperature_factor(T) = ((T-T_max)*(T-T_min)^2)/((T_opt-T_min)*(temperature_factor_g(T)-temperature_factor_f(T))) #unitless
    ## opt, min, max temperatures given by Krishnan et al 
    ##temperature factor obtained from model given by Greene et al https://www.osti.gov/servlets/purl/1806213

    biomass_specific_growth_rate(T, S) = max_biomass_specific_growth_rate.*temperature_factor(T).*salinity_factor(S) #1/hr
    
    #Seawater Buffer System
    pH_inter_data = zeros(1001)

    csv_reader1 = CSV.File("pH_inter.csv", header=["col1"])
    for (i,row) in enumerate(csv_reader1)
        pH_inter_data[i] = convert(Float64, row.col1)   
     
    end
 
    vector1 = range(1E-09,70001,1001) #uses DIC

    pH_interp = LinearInterpolator(vector1, pH_inter_data) #function that uses DIC as input, pH as output
    pH_init = pH_interp(DIC_init)

    CO2_inter_data = zeros(1001)
    csv_reader2 = CSV.File("CO2_inter.csv", header=["col1"])

    for (i,row) in enumerate(csv_reader2)
        CO2_inter_data[i] = convert(Float64, row.col1)    #g/m3
    end

    CO2_interp = LinearInterpolator(vector1, CO2_inter_data) #function that uses DIC as input, CO2 in mol/L as output

    ## Salinity Properties
    salinity_in = 35 #g/kg sw
    salinity(T,R_H,W,P,x) = (salinity_in*volumetric_flow_rate_o)/(volumetric_flow_rate(T,W,R_H,P,x)) #kg salt in a section/kg sw

    params = (; num_odes_y,
                num_odes_z,
                time_end,
                reference_pressure,
                stefan_boltzmann_constant,
                density_air,
                dynamic_viscosity_air,
                thermal_conductivity_air,
                specific_heat_capacity_air,
                prandtl_air,
                emissivity_air,
                density_water,
                dynamic_viscosity_water,                          
                specific_heat_capacity_water,
                thermal_conductivity_water,
                solar_reflectance_water,
                diffusion_coeff_water_air,
                saturated_vapor_pressure_water_air,
                heat_vaporization_water,
                emissivity_water,
                diffusion_coeff_co2_water,
                solubility_co2_water,
                thermal_diffusivity_concrete,
                thermal_conductivity_concrete,
                global_horizontal_irradiance_data,
                ambient_temperature_data,
                relative_humidity_data,
                wind_speed_data,
                data_begin,
                lengths,
                reactor_length,
                reactor_width,
                reactor_initial_liquid_level,
                evaporation_constant,
                ambient_humidity_ratio,
                surface_humidity_ratio,
                evaporation_mass_flux,
                flow_rates,
                volumetric_flow_rate,
                height,
                velocity_profile_lam,
                hydraulic_diameter,
                reynolds_number,
                input_temperature,
                ground_temperature,
                input_biomass_concentration,
                max_biomass_specific_growth_rate,
                salinity_factor,
                temperature_factor,
                biomass_specific_growth_rate,
                co2_per_biomass,
                DIC_init,
                pH_interp,
                CO2_interp,
                biomass_diffusion_coefficient_y,
                biomass_diffusion_coefficient_z,
                evaporation_heat_flux,
                salinity_in,
                co2_init,
                salinity,
                volumetric_flow_rate_o,
                strip_position,
                volumetric_flow_rate_strip,
                strip_concentration,
                real_length,
                s_conc,
                pH_init
                )


    return params
end






