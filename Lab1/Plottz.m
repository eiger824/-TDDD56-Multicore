%% Naive implementation

close all;
x = [1:8];
y = [   
        0.141117,
        0.069776,
        0.080108,
        0.054510,
        0.052942,
        0.042066,
        0.045068,
        0.046363,
    ];
plot(x,y);

%% Our loadbalancing

x2 = [1:8];
y2 = [
        0.158897,
        0.075789,
        0.046435,
        0.035345,
        0.036267,
        0.035388,
        0.035622,
        0.037534
    ]

plot(x,y); 
hold on;
plot(x2,y2);




