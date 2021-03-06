###############################################################################
# 19/01/2016
# Author: Alastair V Harry - alastair.harry@gmail.com
# Deptartment of Fisheries Western Australia & 
# Centre For Sustainable Tropical Fisheries & Aquaculture
# James Cook University, Townsville
# 
# Description: An R-script for doing a multi-model analysis of fish growth
# and plotting with confidence intervals. This version includes six
# deterministic growth models. Style of outputs follows Walker (2005) 
# `Reproduction in fisheries science.`
#
# Example data are used from: Harry et al (2013) Age, growth, and reproductive 
# biology of the spot-tail shark, Carcharhinus sorrah, and the Australian
# blacktip shark, C. tilstoni, from the Great Barrier Reef World Heritage Area,
# north-eastern Australia. Marine and Freshwater Research
#
################################################################################

# Clear console and remove list objects
cat("\014");rm(list=ls())

# Specify libraries required for analysis
library(nlstools)
library(RCurl)
library(ggplot2)
library(dplyr)
library(propagate)

# Load example data from github
# If sss.verifypeer = TRUE doesn't work, set to false, but read this:
# http://ademar.name/blog/2006/04/curl-ssl-certificate-problem-v.html
#data <- getURL("https://raw.githubusercontent.com/alharry/spot-tail/master/SSS.csv",ssl.verifypeer = FALSE)%>%
#        textConnection()%>%
#        read.csv(sep=",")%>%
#        tbl_df()
data<-read.csv("SSS.csv")
# Skip to here and load your data if you don't want to use the 
# example dataset

# Specify sex: "m", "f" or "both"
sex="f"

# Prepare data for non-linear model fitting and plotting. Choose starting values
# and define extremes of plotting areas

# Specify an appropriate length at birth, L0, for use in 2 parameter models
Mini<-L0<-525

# Specify dimensions for plotting (used at the end of this script)
Max.Overall<-data$STL%>%na.omit%>%max()%>%ceiling() 
Max.Plot<-data$AgeAgree%>%na.omit%>%max()%>%ceiling()

# Specify subset of data to be used (i.e. males or females or both) and keep
# an extra data frame with all the data (data1)
data1<-data
data<-if(sex=="both"){data}else{filter(data,Sex==sex)}
Max<-max(na.omit(data$STL)) 
Max.Age<-max(na.omit(data$AgeAgree))

# Routine for getting starting values for asymptotic growth models using Ford-Walford method
# for Linf and K. To estimate L0, a quadratic is fit to the mean length at
# age data, and the intercept extracted. This section I got from Derek Ogle's
# FishR. 
mean.age<-with(data,tapply(STL,round(AgeAgree),mean,na.rm=T)) # Mean STL at age
Lt1<-mean.age[2:length(mean.age)] # Length at time t+1
Lt<-mean.age[1:length(mean.age)-1] # Length at time t
pars<-lm(Lt1~Lt)$coef # Regression of Lt1 against Lt
start.k<- abs(-log(pars[2])) # Get starting value for k, Linf and L0
start.linf<-abs(pars[1]/(1-pars[2])) 
start.L0<-lm(mean.age~poly(as.numeric(names(mean.age)), 2, raw=TRUE))$coef[1]

# Remove all non-essential data from the data frame
data<-na.omit(dplyr::select(data,STL,AgeAgree))
names(data)<-c("STL","Age")

# Create a set of candidate models for MMI comparison. 
# Three commonly used non-linear growth models are listed below.
# The functions have each been solved in such a way that
# they explicitly include the y-intercept (L0, length at time zero) as a
# fitted model parameter, and differ from the more common form that explicitly
# includes the x-intercept (t0, hypothetical age at zero length). The L0 
# parameterisation makes more biological sense for sharks since they are born 
# live and fully formed. 
# In instances where you don't have a good data for very young individuals,
# it is probably best to use the 2 parameter versions, otherwise the size
# at birth will be overestimated by the model. 
# Constraining the model to have only 2 parameters instead of 3 causes a bias
# in the other parameters, so if you have good data for all sizes its best to
# use the 3 parameter version. 
# In my opinion it doesn't make much sense to include both 2 and 3 parameter
# versions of the same model in your set of candidate models.

#G1 - 3 parameter VB
g1<-STL~abc2+(abc1-abc2)*(1-exp(-abc3*Age))
g1.Start<-list(abc1=start.linf,abc2=start.L0,abc3=start.k)
g1.name<-"VB3"
# G2 - 2 parameter VB
g2<- substitute(STL~L0+(ab1-L0)*(1-exp(-ab2*Age)),list(L0=L0))
g2.Start<-list(ab1=start.linf,ab2=start.k)
g2.name<-"VB2"
# G3 - 3 parameter Gompertz
g3<- STL~ abc2*exp(log(abc1/abc2)*(1-exp(-abc3*Age)))
g3.Start<-list(abc1=start.linf,abc2=start.L0,abc3=start.k)
g3.name<-"GOM3"
# G4 - 2 parameter Gompertz
g4<- substitute(STL~L0*exp(log(ab1/L0)*(1-exp(-ab2*Age))),list(L0=L0))
g4.Start<-list(ab1=start.linf,ab2=start.k)
g4.name<-"GOM2"
# G5 - 3 parameter Logistic model
g5<- STL~ (abc1*abc2*exp(abc3*Age))/(abc1+abc2*((exp(abc3*Age))-1))
g5.Start<-list(abc1=start.linf, abc2=start.L0, abc3=start.k)
g5.name<-"LOGI3"
# G6 - 2 parameter Logistic model
g6<- substitute(STL~ (ab1*L0*exp(ab2*Age))/(ab1+L0*((exp(ab2*Age))-1)),list(L0=L0))
g6.Start<-list(ab1=start.linf,ab2=start.k)
g6.name<-"LOGI2"


# Select the list of candidate models to compare.
Models<-list(g1,g2,g3,g4,g5,g6)
Start<-list(g1.Start,g2.Start,g3.Start,g4.Start,g5.Start,g6.Start)
Mod.names<-c(g1.name,g2.name,g3.name,g4.name,g5.name,g6.name)
Mods<-length(Models)
Results<-list()

# Fit growth models, outputs are stored as a list object called Results. Models
# are fit using nonlinear least squares 
Results[[1]]<-nls(Models[[1]],data=data,start=Start[[1]],algorithm="port")
Results[[2]]<-nls(Models[[2]],data=data,start=Start[[2]],algorithm="port")
Results[[3]]<-nls(Models[[3]],data=data,start=Start[[3]],algorithm="port")
Results[[4]]<-nls(Models[[4]],data=data,start=Start[[4]],algorithm="port")
Results[[5]]<-nls(Models[[5]],data=data,start=Start[[5]],algorithm="port")
Results[[6]]<-nls(Models[[6]],data=data,start=Start[[6]],algorithm="port")

# Put best fit paramters into a matrix
par.matrix<-data.frame(matrix(NA,Mods,6))
names(par.matrix)<-c('abc1','SE','abc2','SE','abc3','SE')
for(i in 1:Mods){
	npars=length(coef(Results[[i]]))*2
	mod.pars<-c(t(summary(Results[[i]])$par[,c(1,2)]))
	      for(j in 1:npars){
		    par.matrix[i,j]<-mod.pars[j]
		  }
		}

# Look at diagnostic plots
# for(i in 1:Mods){plot(nlsResiduals(Results[[i]]))}

# Run the multi-model inference comparison. The following section calculates
# AIC values, AIC differences, AIC weights and residual standard errors
AIC.vals<-lapply(Results,AIC)%>%unlist()
Residual.Standard.Error<-lapply(Results,function(x){(sum(residuals(x)^2)/df.residual(x))%>%sqrt()})%>%unlist()
AIC.dif<-AIC.vals-min(AIC.vals)
AIC.weight= round((exp(-0.5*AIC.dif))/(sum(exp(-0.5*AIC.dif))),4)*100

# Store output of MMI analysis. This is the important bit.
MMI.Analysis<-data.frame(`AIC`=AIC.vals,`Delta AIC`=AIC.dif,w=AIC.weight,RSE=Residual.Standard.Error,
		par.matrix, row.names=Mod.names)%>%
    signif(4) # Round to four significant figures

# Calculate confidence and prediction intervals and plot output

# Specify values of age that you want to predict length over
newAge=seq(0,Max.Age,length.out=50)

# Confidence intervals (1-ALPHA)
ALPHA<-0.05

# Model with lowest AIC value for plotting
bestMod<-Results[[which(AIC.dif==0)]]

# Calculate confidence intervals using 2nd order Taylor expansion from
# propagate package
Output<-data.frame(Age=newAge,
                   predictNLS(bestMod,newdata=data.frame(Age=newAge),alpha=ALPHA,
                   interval="confidence",do.sim=FALSE)$summary[,c(1,3,5,6)])
names(Output)=c("Age","STL","SD","cLower","cUpper")

# Calculate predition intervals
Output$pLower<-Output$STL-qt(1 - ALPHA/2, df.residual(bestMod))  * sqrt(Output$SD^2 + summary(bestMod)$sigma^2)
Output$pUpper<-Output$STL+qt(1 - ALPHA/2, df.residual(bestMod))  * sqrt(Output$SD^2 + summary(bestMod)$sigma^2)

# Plot data
p<-ggplot(Output,aes(x=Age,y=STL))+geom_line()+
  # confidence intervals
  geom_line(aes(y=cUpper),linetype="dashed")+geom_line(aes(y=cLower),linetype="dashed")+
  # prediction intervals
  geom_line(aes(y=pUpper),linetype="dotted")+geom_line(aes(y=pLower),linetype="dotted")+
  # raw data
  geom_point(data=data,aes(x=Age,y=STL))+xlab("Age (Years)")+ylab("TL (cm)")+
  theme(panel.background=element_blank())+theme_classic()+xlim(0,Max.Plot)+ylim(Mini*0.9,Max.Overall*1.1)
p

# Save analysis
#write.csv(MMI.Analysis, "MMI.Analysis.csv")
Results<-list(MMI.Analysis,bestMod,Output)

